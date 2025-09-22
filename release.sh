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

# -----------------------------
# Parse arguments
# -----------------------------
if [ $# -eq 0 ]; then
  # No args - use VERSION file
  if [ ! -f VERSION ]; then
    echo "❌ No VERSION file found!"
    echo "   Create one: echo '0.1.0' > VERSION"
    exit 1
  fi
  VERSION=$(cat VERSION | tr -d '[:space:]')
  echo "📊 Using VERSION file: $VERSION"
else
  VERSION="$1"
  echo "📊 Using specified version: $VERSION"
fi

# Validate version format
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "❌ Invalid version format: $VERSION"
  exit 1
fi

VERSION_BRANCH="$VERSION"
VERSION_TAG="v$VERSION"

echo ""
echo "🎯 Release Plan:"
echo "   Version: $VERSION"
echo "   Branch:  $VERSION_BRANCH"
echo "   Tag:     $VERSION_TAG"
echo ""

# -----------------------------
# Check current branch
# -----------------------------
CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
echo "📍 Current branch: $CURRENT_BRANCH"

# -----------------------------
# Check for uncommitted changes
# -----------------------------
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "⚠️  Uncommitted changes detected!"
  git status --short
  if ! confirm "Commit these changes?"; then
    echo "❌ Please commit or stash first"
    exit 1
  fi
  read -r -p "Commit message: " msg
  git add -A
  git commit -m "$msg"
fi

# -----------------------------
# Fetch latest
# -----------------------------
echo "📥 Fetching latest..."
git fetch origin --tags --prune

# -----------------------------
# Handle branch
# -----------------------------
if [ "$CURRENT_BRANCH" != "$VERSION_BRANCH" ]; then
  if git show-ref --verify --quiet "refs/heads/$VERSION_BRANCH"; then
    echo "📋 Switching to branch '$VERSION_BRANCH'..."
    git checkout "$VERSION_BRANCH"
  else
    echo "🌿 Creating branch '$VERSION_BRANCH'..."
    git checkout -b "$VERSION_BRANCH"
  fi
else
  echo "✅ Already on branch '$VERSION_BRANCH'"
fi

# -----------------------------
# Update files if needed
# -----------------------------
CHANGES_MADE=false

# Update VERSION file
if [ ! -f VERSION ] || [ "$(cat VERSION | tr -d '[:space:]')" != "$VERSION" ]; then
  echo "📝 Updating VERSION file to $VERSION"
  echo "$VERSION" > VERSION
  git add VERSION
  CHANGES_MADE=true
fi

# Update cargo-generate.toml
if [ -f "cargo-generate.toml" ]; then
  if ! grep -q "^branch = \"$VERSION_BRANCH\"" cargo-generate.toml; then
    echo "📝 Updating cargo-generate.toml branch to '$VERSION_BRANCH'"
    
    if grep -q "^branch = " cargo-generate.toml; then
      # Update existing
      if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/^branch = .*/branch = \"$VERSION_BRANCH\"/" cargo-generate.toml
      else
        sed -i "s/^branch = .*/branch = \"$VERSION_BRANCH\"/" cargo-generate.toml
      fi
    else
      # Add new
      if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "/^\[template\]/a\\
branch = \"$VERSION_BRANCH\"" cargo-generate.toml
      else
        sed -i "/^\[template\]/a\\branch = \"$VERSION_BRANCH\"" cargo-generate.toml
      fi
    fi
    
    git add cargo-generate.toml
    CHANGES_MADE=true
  fi
fi

# -----------------------------
# Commit if changes made
# -----------------------------
if [ "$CHANGES_MADE" = true ]; then
  echo "💾 Committing changes..."
  git commit -m "chore(release): prepare version $VERSION"
fi

# -----------------------------
# Push branch
# -----------------------------
echo "⬆️  Pushing branch '$VERSION_BRANCH'..."
git push origin "$VERSION_BRANCH" 2>/dev/null || git push --set-upstream origin "$VERSION_BRANCH"

# -----------------------------
# Handle tag
# -----------------------------
echo ""
echo "🏷️  Handling tag '$VERSION_TAG'..."

# Check if tag exists
TAG_EXISTS=false
if git tag -l | grep -q "^$VERSION_TAG$"; then
  TAG_EXISTS=true
  echo "   Local tag exists"
fi

if git ls-remote --tags origin | grep -q "refs/tags/$VERSION_TAG"; then
  TAG_EXISTS=true
  echo "   Remote tag exists"
fi

if [ "$TAG_EXISTS" = true ]; then
  if confirm "Tag '$VERSION_TAG' exists. Recreate it?"; then
    echo "🗑  Deleting old tag..."
    git tag -d "$VERSION_TAG" 2>/dev/null || true
    git push origin ":refs/tags/$VERSION_TAG" 2>/dev/null || true
  else
    echo "✅ Keeping existing tag"
    echo ""
    echo "📦 Install command:"
    echo "   cargo generate --git $(git config --get remote.origin.url) --branch $VERSION_BRANCH --name myapp"
    exit 0
  fi
fi

echo "✨ Creating tag '$VERSION_TAG'..."
git tag -a "$VERSION_TAG" -m "Release $VERSION"

echo "⬆️  Pushing tag..."
git push origin "$VERSION_TAG"

# -----------------------------
# Done!
# -----------------------------
echo ""
echo "✅ Release $VERSION completed!"
echo ""
echo "📦 Install command:"
echo "   cargo generate --git $(git config --get remote.origin.url) --branch $VERSION_BRANCH --name myapp"
echo ""
echo "📌 Next: Create GitHub release from tag '$VERSION_TAG'"