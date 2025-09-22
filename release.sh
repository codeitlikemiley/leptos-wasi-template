#!/usr/bin/env bash
set -euo pipefail

# -----------------------------
# Helper Functions
# -----------------------------
confirm() {
  read -r -p "$1 (y/N): " response
  case "$response" in
    [yY][eE][sS]|[yY]) true ;;
    *) false ;;
  esac
}

normalize_branch_name() {
  local branch="$1"
  echo "$branch" | sed 's#^refs/heads/##'
}

# -----------------------------
# Validate input
# -----------------------------
if [ $# -ne 1 ]; then
  echo "Usage: ./release.sh <version>"
  echo "Example: ./release.sh 0.1.3"
  exit 1
fi

VERSION="$1"
TAG="v$VERSION"

# Validate version format
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "❌ Invalid version format: $VERSION"
  echo "Format must be: MAJOR.MINOR.PATCH (e.g., 0.1.3)"
  exit 1
fi

# -----------------------------
# Detect and normalize current branch
# -----------------------------
RAW_BRANCH=$(git symbolic-ref HEAD 2>/dev/null || echo "")
if [ -z "$RAW_BRANCH" ]; then
  echo "❌ Not on any branch (detached HEAD state)."
  exit 1
fi

CURRENT_BRANCH=$(normalize_branch_name "$RAW_BRANCH")

echo "⚡ Preparing release: $TAG from branch $CURRENT_BRANCH"

# -----------------------------
# Confirm before proceeding
# -----------------------------
if ! confirm "⚠️  You are on '$CURRENT_BRANCH'. Proceed with release $TAG?"; then
  echo "❌ Release aborted."
  exit 1
fi

# -----------------------------
# Fetch latest remote changes
# -----------------------------
echo "📥 Fetching latest changes from origin..."
git fetch origin --tags

REMOTE_BRANCH="origin/$CURRENT_BRANCH"

# -----------------------------
# Auto-rebase with local wins
# -----------------------------
if git show-ref --verify --quiet "refs/remotes/$REMOTE_BRANCH"; then
  echo "📦 Rebasing local branch onto $REMOTE_BRANCH (preferring LOCAL changes)..."
  if ! git rebase -X ours "$REMOTE_BRANCH"; then
    echo "⚠️ Auto-rebase failed, forcing merge strategy to keep LOCAL changes..."
    git rebase --abort
    git merge -X ours "$REMOTE_BRANCH" || {
      echo "❌ Merge failed, please resolve conflicts manually and rerun."
      exit 1
    }
  fi
else
  echo "ℹ️ Remote branch $REMOTE_BRANCH does not exist, skipping rebase."
fi

# -----------------------------
# Update VERSION file
# -----------------------------
if [ ! -f VERSION ]; then
  echo "0.0.0" > VERSION
fi

PREV_VERSION=$(cat VERSION || echo "none")

if [ "$PREV_VERSION" != "$VERSION" ]; then
  echo "$VERSION" > VERSION
  git add VERSION
  git commit -m "chore(release): bump version to $VERSION" || echo "ℹ️ No changes to commit."
else
  echo "ℹ️ VERSION already at $VERSION, skipping commit."
fi

# -----------------------------
# Handle tags
# -----------------------------
if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "🗑 Deleting existing local tag: $TAG"
  git tag -d "$TAG"
else
  echo "ℹ️ No existing local tag: $TAG"
fi

if git ls-remote --tags origin | grep -q "refs/tags/$TAG"; then
  echo "🗑 Deleting existing remote tag: $TAG"
  git push origin --delete "$TAG"
else
  echo "ℹ️ No existing remote tag: $TAG"
fi

echo "✨ Creating new tag: $TAG"
git tag "$TAG"

# -----------------------------
# Push with safety checks
# -----------------------------
echo "🚀 Ready to push branch '$CURRENT_BRANCH' and tag '$TAG'"
if confirm "⚠️  This will overwrite the remote branch and tag if needed. Continue?"; then
  echo "📥 Fetching latest remote refs before push..."
  git fetch origin --prune --tags

  echo "⬆️ Pushing branch '$CURRENT_BRANCH' explicitly..."
  git push --force-with-lease origin "refs/heads/$CURRENT_BRANCH:refs/heads/$CURRENT_BRANCH"

  echo "⬆️ Pushing tag '$TAG' explicitly..."
  git push --force origin "refs/tags/$TAG:refs/tags/$TAG"

  echo "✅ Release complete: $TAG"
else
  echo "❌ Push aborted."
fi
