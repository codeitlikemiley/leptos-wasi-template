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

# Compare semantic versions
# Returns: 0 if v1 > v2, 1 if v1 <= v2
version_gt() {
  local v1="$1"
  local v2="$2"
  
  # Split versions into arrays
  IFS='.' read -ra V1_PARTS <<< "$v1"
  IFS='.' read -ra V2_PARTS <<< "$v2"
  
  # Compare major
  if [ "${V1_PARTS[0]}" -gt "${V2_PARTS[0]}" ]; then
    return 0
  elif [ "${V1_PARTS[0]}" -lt "${V2_PARTS[0]}" ]; then
    return 1
  fi
  
  # Compare minor
  if [ "${V1_PARTS[1]}" -gt "${V2_PARTS[1]}" ]; then
    return 0
  elif [ "${V1_PARTS[1]}" -lt "${V2_PARTS[1]}" ]; then
    return 1
  fi
  
  # Compare patch
  if [ "${V1_PARTS[2]}" -gt "${V2_PARTS[2]}" ]; then
    return 0
  else
    return 1
  fi
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
VERSION_BRANCH="$VERSION"      # Branch name: 0.1.3
VERSION_TAG="v$VERSION"        # Tag name: v0.1.3

# Validate version format
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "❌ Invalid version format: $VERSION"
  echo "Format must be: MAJOR.MINOR.PATCH (e.g., 0.1.3)"
  exit 1
fi

# -----------------------------
# Check current VERSION and validate it's newer
# -----------------------------
if [ -f VERSION ]; then
  CURRENT_VERSION=$(cat VERSION | tr -d '[:space:]')
  echo "📊 Current version: $CURRENT_VERSION"
  echo "📊 New version: $VERSION"
  
  if [ "$CURRENT_VERSION" = "$VERSION" ]; then
    echo "❌ Version $VERSION is already the current version!"
    echo "   No release needed."
    exit 1
  fi
  
  if ! version_gt "$VERSION" "$CURRENT_VERSION"; then
    echo "❌ New version $VERSION must be greater than current version $CURRENT_VERSION!"
    echo ""
    echo "   Current: $CURRENT_VERSION"
    echo "   Attempted: $VERSION"
    echo ""
    echo "   Valid next versions could be:"
    
    # Suggest next versions
    IFS='.' read -ra PARTS <<< "$CURRENT_VERSION"
    echo "   - Patch: ${PARTS[0]}.${PARTS[1]}.$((PARTS[2] + 1))"
    echo "   - Minor: ${PARTS[0]}.$((PARTS[1] + 1)).0"
    echo "   - Major: $((PARTS[0] + 1)).0.0"
    exit 1
  fi
  
  echo "✅ Version bump validated: $CURRENT_VERSION → $VERSION"
else
  echo "ℹ️  No VERSION file found, will create with version $VERSION"
  CURRENT_VERSION="0.0.0"
fi

echo ""
echo "🎯 Release Plan:"
echo "   Version: $VERSION"
echo "   Branch:  $VERSION_BRANCH (for cargo generate)"
echo "   Tag:     $VERSION_TAG (for GitHub releases)"
echo ""

# -----------------------------
# SAFETY CHECK: Uncommitted changes
# -----------------------------
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "⚠️  You have uncommitted changes:"
  git status --short
  echo ""
  
  if ! confirm "Commit these changes before proceeding?"; then
    echo "❌ Please commit or stash your changes first!"
    echo "   To stash: git stash"
    echo "   To commit: git add -A && git commit -m 'your message'"
    exit 1
  else
    echo "📝 Enter commit message:"
    read -r commit_message
    git add -A
    git commit -m "$commit_message"
  fi
fi

# -----------------------------
# Get current branch
# -----------------------------
CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")

if [ -z "$CURRENT_BRANCH" ]; then
  echo "❌ Not on any branch (detached HEAD)"
  exit 1
fi

echo "📍 Current branch: $CURRENT_BRANCH"

# -----------------------------
# Fetch latest changes
# -----------------------------
echo "📥 Fetching latest changes..."
git fetch origin --tags --prune

# -----------------------------
# Handle branch scenarios
# -----------------------------
if [ "$CURRENT_BRANCH" = "$VERSION_BRANCH" ]; then
  echo "✅ Already on version branch '$VERSION_BRANCH'"
  
  # Check if this is a different version branch than expected
  if [ -f VERSION ]; then
    BRANCH_VERSION=$(cat VERSION | tr -d '[:space:]')
    if [ "$BRANCH_VERSION" != "$VERSION" ] && [ "$BRANCH_VERSION" != "0.0.0" ]; then
      echo "⚠️  Branch $VERSION_BRANCH has VERSION file with $BRANCH_VERSION"
      if ! confirm "Continue and update to $VERSION?"; then
        echo "❌ Release aborted"
        exit 1
      fi
    fi
  fi
  
elif [[ "$CURRENT_BRANCH" == "main" || "$CURRENT_BRANCH" == "master" ]]; then
  echo "📍 On $CURRENT_BRANCH branch"
  
  if git show-ref --verify --quiet "refs/heads/$VERSION_BRANCH"; then
    echo "ℹ️  Version branch '$VERSION_BRANCH' already exists"
    git checkout "$VERSION_BRANCH"
  else
    echo "🌿 Creating new version branch '$VERSION_BRANCH'..."
    git checkout -b "$VERSION_BRANCH"
  fi

else
  echo "⚠️  You're on '$CURRENT_BRANCH'"
  
  if git show-ref --verify --quiet "refs/heads/$VERSION_BRANCH"; then
    if confirm "Switch to existing branch '$VERSION_BRANCH'?"; then
      git checkout "$VERSION_BRANCH"
    else
      echo "❌ Release aborted"
      exit 1
    fi
  else
    if confirm "Create new version branch '$VERSION_BRANCH' from current branch?"; then
      git checkout -b "$VERSION_BRANCH"
    else
      echo "❌ Release aborted"
      exit 1
    fi
  fi
fi

# -----------------------------
# Update VERSION file
# -----------------------------
echo "📝 Updating VERSION file: $CURRENT_VERSION → $VERSION"
echo "$VERSION" > VERSION
git add VERSION

# -----------------------------
# Update cargo-generate.toml branch field
# -----------------------------
if [ -f "cargo-generate.toml" ]; then
  echo "📝 Updating cargo-generate.toml branch field to '$VERSION_BRANCH'"
  
  # Check if branch field exists
  if grep -q "^branch = " cargo-generate.toml; then
    # Update existing branch field
    if [[ "$OSTYPE" == "darwin"* ]]; then
      # macOS
      sed -i '' "s/^branch = .*/branch = \"$VERSION_BRANCH\"/" cargo-generate.toml
    else
      # Linux
      sed -i "s/^branch = .*/branch = \"$VERSION_BRANCH\"/" cargo-generate.toml
    fi
  else
    # Add branch field after cargo_generate_version if it doesn't exist
    if [[ "$OSTYPE" == "darwin"* ]]; then
      sed -i '' "/^cargo_generate_version = /a\\
branch = \"$VERSION_BRANCH\"" cargo-generate.toml
    else
      sed -i "/^cargo_generate_version = /a\\branch = \"$VERSION_BRANCH\"" cargo-generate.toml
    fi
  fi
  
  git add cargo-generate.toml
  
  # Show the changes
  echo "📋 Updated cargo-generate.toml:"
  grep -A1 "^\[template\]" cargo-generate.toml | head -3
fi

# -----------------------------
# Commit version changes
# -----------------------------
if ! git diff --cached --quiet; then
  echo "💾 Committing version changes..."
  git commit -m "chore(release): bump version to $VERSION

- Updated VERSION file to $VERSION
- Updated cargo-generate.toml branch to $VERSION_BRANCH"
else
  echo "ℹ️  No changes to commit"
fi

# -----------------------------
# Push branch
# -----------------------------
echo "⬆️  Pushing branch '$VERSION_BRANCH'..."
if git show-ref --verify --quiet "refs/remotes/origin/$VERSION_BRANCH"; then
  git push origin "$VERSION_BRANCH"
else
  git push --set-upstream origin "$VERSION_BRANCH"
fi

# -----------------------------
# Handle tag
# -----------------------------
if git rev-parse "$VERSION_TAG" >/dev/null 2>&1; then
  echo "🗑  Deleting existing local tag: $VERSION_TAG"
  git tag -d "$VERSION_TAG"
fi

if git ls-remote --tags origin | grep -q "refs/tags/$VERSION_TAG"; then
  if confirm "Delete existing remote tag '$VERSION_TAG'?"; then
    git push origin ":refs/tags/$VERSION_TAG"
  fi
fi

echo "✨ Creating tag: $VERSION_TAG"
git tag -a "$VERSION_TAG" -m "Release $VERSION

cargo generate --git $(git config --get remote.origin.url) --branch $VERSION_BRANCH --name myapp"

echo "⬆️  Pushing tag '$VERSION_TAG'..."
git push origin "$VERSION_TAG"

# -----------------------------
# Success
# -----------------------------
echo ""
echo "✅ Release $VERSION completed successfully!"
echo ""
echo "📋 Summary:"
echo "   • VERSION file: $CURRENT_VERSION → $VERSION"
echo "   • Branch: $VERSION_BRANCH"
echo "   • Tag: $VERSION_TAG"
echo "   • cargo-generate.toml: branch = \"$VERSION_BRANCH\""
echo ""
echo "📦 Users can install with:"
echo "   cargo generate --git $(git config --get remote.origin.url) --branch $VERSION_BRANCH --name myapp"
echo ""
echo "📌 Next steps:"
echo "   1. Create GitHub release from tag '$VERSION_TAG'"
echo "   2. Test: cargo generate --git $(git config --get remote.origin.url) --branch $VERSION_BRANCH --name test"