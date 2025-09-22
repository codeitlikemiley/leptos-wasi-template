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
# Check for naming conflicts
# -----------------------------
echo "🔍 Checking for branch/tag conflicts..."

# Check if there's a branch with the same name as our tag
if git show-ref --verify --quiet "refs/heads/$TAG"; then
  echo "⚠️  WARNING: You have a branch named '$TAG' which conflicts with the tag name!"
  echo "   This will cause ambiguity issues."
  
  if confirm "Delete the branch '$TAG' to avoid conflicts?"; then
    # Check if it's the current branch
    CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
    if [ "$CURRENT_BRANCH" = "$TAG" ]; then
      echo "📌 Switching to main/master first..."
      git checkout main 2>/dev/null || git checkout master 2>/dev/null || {
        echo "❌ Cannot switch away from $TAG branch. Please manually switch branches first."
        exit 1
      }
    fi
    
    # Delete local branch
    echo "🗑 Deleting local branch: $TAG"
    git branch -D "$TAG"
    
    # Delete remote branch if exists
    if git ls-remote --heads origin | grep -q "refs/heads/$TAG"; then
      echo "🗑 Deleting remote branch: $TAG"
      git push origin --delete "refs/heads/$TAG"
    fi
  else
    echo "❌ Cannot proceed with conflicting branch name. Please rename or delete the branch '$TAG'"
    exit 1
  fi
fi

# -----------------------------
# Detect current branch
# -----------------------------
RAW_BRANCH=$(git symbolic-ref HEAD 2>/dev/null || echo "")
if [ -z "$RAW_BRANCH" ]; then
  echo "❌ Not on any branch (detached HEAD state)."
  exit 1
fi

CURRENT_BRANCH=$(normalize_branch_name "$RAW_BRANCH")

# -----------------------------
# Determine release strategy
# -----------------------------
echo "⚡ Preparing release: $TAG"
echo "📍 Current branch: $CURRENT_BRANCH"

# Option 1: Release from main/master branch (recommended)
if [[ "$CURRENT_BRANCH" == "main" || "$CURRENT_BRANCH" == "master" ]]; then
  echo "✅ Releasing from $CURRENT_BRANCH branch"
  RELEASE_BRANCH="$CURRENT_BRANCH"
  
# Option 2: Already on a release branch
elif [[ "$CURRENT_BRANCH" =~ ^release/.+ ]]; then
  echo "✅ Already on release branch: $CURRENT_BRANCH"
  RELEASE_BRANCH="$CURRENT_BRANCH"
  
# Option 3: Create a new release branch
else
  RELEASE_BRANCH="release/$VERSION"
  echo "⚠️  Not on main/master or release branch."
  
  if confirm "Create new release branch '$RELEASE_BRANCH' from current branch?"; then
    # Check if release branch already exists
    if git show-ref --verify --quiet "refs/heads/$RELEASE_BRANCH"; then
      echo "⚠️  Branch '$RELEASE_BRANCH' already exists locally."
      if confirm "Switch to existing branch?"; then
        git checkout "$RELEASE_BRANCH"
      else
        echo "❌ Release aborted."
        exit 1
      fi
    else
      echo "🌿 Creating new release branch: $RELEASE_BRANCH"
      git checkout -b "$RELEASE_BRANCH"
    fi
  elif confirm "Continue release from current branch '$CURRENT_BRANCH'?"; then
    RELEASE_BRANCH="$CURRENT_BRANCH"
  else
    echo "❌ Release aborted."
    exit 1
  fi
fi

# -----------------------------
# Fetch latest remote changes
# -----------------------------
echo "📥 Fetching latest changes from origin..."
git fetch origin --tags --prune

# -----------------------------
# Sync with remote if branch exists
# -----------------------------
REMOTE_BRANCH="origin/$RELEASE_BRANCH"

if git show-ref --verify --quiet "refs/remotes/$REMOTE_BRANCH"; then
  echo "📦 Syncing with $REMOTE_BRANCH..."
  
  # Check if we're behind
  LOCAL_COMMIT=$(git rev-parse HEAD)
  REMOTE_COMMIT=$(git rev-parse "$REMOTE_BRANCH")
  
  if [ "$LOCAL_COMMIT" != "$REMOTE_COMMIT" ]; then
    echo "⚠️  Local and remote branches have diverged."
    if confirm "Pull and merge remote changes?"; then
      git pull origin "$RELEASE_BRANCH" --rebase=false -X ours || {
        echo "❌ Merge failed, please resolve conflicts manually."
        exit 1
      }
    fi
  else
    echo "✅ Already in sync with remote."
  fi
else
  echo "ℹ️  Remote branch $REMOTE_BRANCH does not exist yet."
fi

# -----------------------------
# Update VERSION file
# -----------------------------
if [ ! -f VERSION ]; then
  echo "0.0.0" > VERSION
fi

PREV_VERSION=$(cat VERSION || echo "none")

if [ "$PREV_VERSION" != "$VERSION" ]; then
  echo "📝 Updating VERSION file: $PREV_VERSION → $VERSION"
  echo "$VERSION" > VERSION
  git add VERSION
  git commit -m "chore(release): bump version to $VERSION" || echo "ℹ️ No changes to commit."
else
  echo "ℹ️ VERSION already at $VERSION"
fi

# -----------------------------
# Handle existing tags safely
# -----------------------------
# Check and delete local tag if exists
if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "🗑 Deleting existing local tag: $TAG"
  git tag -d "$TAG" || true  # Don't fail if tag doesn't exist
else
  echo "ℹ️ No existing local tag: $TAG"
fi

# Check and delete remote tag if exists
if git ls-remote --tags origin | grep -q "refs/tags/$TAG"; then
  echo "⚠️  Remote tag '$TAG' already exists."
  if confirm "Delete existing remote tag?"; then
    echo "🗑 Deleting remote tag: $TAG"
    # Use explicit refs/tags/ to avoid ambiguity
    git push origin ":refs/tags/$TAG" || true
  else
    echo "❌ Cannot create tag that already exists remotely."
    exit 1
  fi
else
  echo "ℹ️ No existing remote tag: $TAG"
fi

# -----------------------------
# Create new tag
# -----------------------------
echo "✨ Creating new tag: $TAG"
git tag -a "$TAG" -m "Release $VERSION"

# -----------------------------
# Final confirmation and push
# -----------------------------
echo ""
echo "📋 Release Summary:"
echo "   Branch: $RELEASE_BRANCH"
echo "   Tag: $TAG"
echo "   Version: $VERSION"
echo ""

if confirm "🚀 Push branch and tag to origin?"; then
  # Push branch first
  echo "⬆️ Pushing branch '$RELEASE_BRANCH'..."
  git push origin "$RELEASE_BRANCH" || {
    echo "⚠️  Branch push failed, trying with --set-upstream..."
    git push --set-upstream origin "$RELEASE_BRANCH"
  }
  
  # Then push tag explicitly with refs/tags/ to avoid ambiguity
  echo "⬆️ Pushing tag '$TAG'..."
  git push origin "refs/tags/$TAG:refs/tags/$TAG"
  
  echo ""
  echo "✅ Release $TAG completed successfully!"
  echo ""
  echo "📌 Next steps:"
  echo "   1. Create a GitHub release from tag '$TAG'"
  echo "   2. If using a release branch, create a PR to merge back to main"
  echo "   3. Delete the release branch after merging (if applicable)"
else
  echo "❌ Push aborted. Tag created locally but not pushed."
  echo "   To push later: git push origin $RELEASE_BRANCH && git push origin refs/tags/$TAG"
fi