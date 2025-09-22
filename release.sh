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
# Returns: 0 if v1 > v2, 1 if v1 <= v2, 2 if equal
version_compare() {
  local v1="$1"
  local v2="$2"
  
  IFS='.' read -ra V1_PARTS <<< "$v1"
  IFS='.' read -ra V2_PARTS <<< "$v2"
  
  # Compare major.minor.patch
  for i in 0 1 2; do
    if [ "${V1_PARTS[$i]}" -gt "${V2_PARTS[$i]}" ]; then
      return 0  # v1 > v2
    elif [ "${V1_PARTS[$i]}" -lt "${V2_PARTS[$i]}" ]; then
      return 1  # v1 < v2
    fi
  done
  
  return 2  # v1 == v2
}

# Get next version suggestions
suggest_next_versions() {
  local current="$1"
  IFS='.' read -ra PARTS <<< "$current"
  echo "   📌 Suggested next versions:"
  echo "      Patch: ${PARTS[0]}.${PARTS[1]}.$((PARTS[2] + 1))"
  echo "      Minor: ${PARTS[0]}.$((PARTS[1] + 1)).0"
  echo "      Major: $((PARTS[0] + 1)).0.0"
}

# -----------------------------
# Parse arguments
# -----------------------------
FORCE_RELEASE=false
VERSION=""
VERSION_SOURCE=""  # Track where version came from

if [ $# -eq 0 ]; then
  # No arguments - auto-detect from VERSION file
  if [ -f VERSION ]; then
    VERSION=$(cat VERSION | tr -d '[:space:]')
    VERSION_SOURCE="file"
    echo "📊 Using version from VERSION file: $VERSION"
  else
    echo "❌ No VERSION file found!"
    echo ""
    echo "   Create a VERSION file first:"
    echo "   echo '0.1.0' > VERSION"
    echo ""
    echo "   Or specify version explicitly:"
    echo "   ./release.sh 0.1.0"
    exit 1
  fi
elif [ $# -eq 1 ]; then
  if [ "$1" = "--force" ]; then
    # Just --force, auto-detect version
    FORCE_RELEASE=true
    if [ -f VERSION ]; then
      VERSION=$(cat VERSION | tr -d '[:space:]')
      VERSION_SOURCE="file"
      echo "📊 Using version from VERSION file: $VERSION (--force)"
    else
      echo "❌ No VERSION file found for --force!"
      exit 1
    fi
  else
    # Version explicitly specified
    VERSION="$1"
    VERSION_SOURCE="argument"
  fi
elif [ $# -eq 2 ] && [ "$2" = "--force" ]; then
  # Version and --force
  VERSION="$1"
  VERSION_SOURCE="argument"
  FORCE_RELEASE=true
else
  echo "Usage: ./release.sh [version] [--force]"
  echo ""
  echo "Examples:"
  echo "  ./release.sh              # Use VERSION file content"
  echo "  ./release.sh 0.1.4        # Release specified version"
  echo "  ./release.sh 0.1.3 --force # Force specific version"
  echo "  ./release.sh --force      # Force VERSION file version"
  exit 1
fi

# Validate version format
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "❌ Invalid version format: $VERSION"
  echo "   Format must be: MAJOR.MINOR.PATCH (e.g., 0.1.3)"
  exit 1
fi

VERSION_BRANCH="$VERSION"      # Branch name: 0.1.3
VERSION_TAG="v$VERSION"        # Tag name: v0.1.3

# -----------------------------
# Check VERSION file and decide if update needed
# -----------------------------
UPDATE_VERSION_FILE=false
CURRENT_VERSION="0.0.0"

if [ -f VERSION ]; then
  CURRENT_VERSION=$(cat VERSION | tr -d '[:space:]')
  
  if [ "$VERSION_SOURCE" = "argument" ]; then
    # Version was specified as argument, need to compare
    version_compare "$VERSION" "$CURRENT_VERSION"
    COMPARE_RESULT=$?
    
    if [ $COMPARE_RESULT -eq 2 ]; then
      # Same version
      echo "✅ Version matches VERSION file: $VERSION"
      echo "   Proceeding with release (no file updates needed)"
    elif [ $COMPARE_RESULT -eq 0 ]; then
      # New version is greater
      echo "📈 Version upgrade: $CURRENT_VERSION → $VERSION"
      UPDATE_VERSION_FILE=true
    else
      # New version is lower
      if [ "$FORCE_RELEASE" = true ]; then
        echo "⚠️  Version downgrade: $CURRENT_VERSION → $VERSION (--force)"
        UPDATE_VERSION_FILE=true
      else
        echo "❌ Version $VERSION is older than current $CURRENT_VERSION!"
        echo ""
        suggest_next_versions "$CURRENT_VERSION"
        echo ""
        echo "   To force: ./release.sh $VERSION --force"
        echo "   To release current: ./release.sh"
        exit 1
      fi
    fi
  else
    # Using VERSION file content, no update needed
    echo "✅ Releasing version from VERSION file: $VERSION"
  fi
else
  # No VERSION file exists
  if [ "$VERSION_SOURCE" = "argument" ]; then
    echo "ℹ️  Creating VERSION file with: $VERSION"
    UPDATE_VERSION_FILE=true
  else
    # This shouldn't happen (caught earlier)
    echo "❌ No VERSION file found!"
    exit 1
  fi
fi

echo ""
echo "🎯 Release Plan:"
echo "   Version: $VERSION"
echo "   Branch:  $VERSION_BRANCH"
echo "   Tag:     $VERSION_TAG"
if [ "$UPDATE_VERSION_FILE" = true ]; then
  echo "   Update VERSION: $CURRENT_VERSION → $VERSION"
fi
if [ "$FORCE_RELEASE" = true ]; then
  echo "   Mode: FORCE"
fi
echo ""

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
# Fetch latest changes
# -----------------------------
echo "📥 Fetching latest changes..."
git fetch origin --tags --prune

# -----------------------------
# Switch to or create version branch
# -----------------------------
if [ "$CURRENT_BRANCH" = "$VERSION_BRANCH" ]; then
  echo "✅ Already on version branch '$VERSION_BRANCH'"
  
  # Sync with remote if exists
  if git show-ref --verify --quiet "refs/remotes/origin/$VERSION_BRANCH"; then
    LOCAL=$(git rev-parse HEAD)
    REMOTE=$(git rev-parse "origin/$VERSION_BRANCH")
    
    if [ "$LOCAL" != "$REMOTE" ]; then
      echo "⚠️  Branch has diverged from remote"
      if confirm "Pull remote changes?"; then
        git pull origin "$VERSION_BRANCH" --rebase=false
      fi
    fi
  fi
else
  # Need to switch to version branch
  if git show-ref --verify --quiet "refs/heads/$VERSION_BRANCH"; then
    echo "📋 Switching to existing branch '$VERSION_BRANCH'"
    git checkout "$VERSION_BRANCH"
    
    # Pull latest if remote exists
    if git show-ref --verify --quiet "refs/remotes/origin/$VERSION_BRANCH"; then
      echo "📥 Pulling latest changes..."
      git pull origin "$VERSION_BRANCH" --rebase=false
    fi
  else
    # Create new version branch
    echo "🌿 Creating new version branch '$VERSION_BRANCH'"
    
    if [[ "$CURRENT_BRANCH" == "main" || "$CURRENT_BRANCH" == "master" ]]; then
      git checkout -b "$VERSION_BRANCH"
    else
      echo "⚠️  You're on '$CURRENT_BRANCH' (not main/master)"
      if confirm "Create branch from current location?"; then
        git checkout -b "$VERSION_BRANCH"
      else
        # Switch to main first
        git checkout main 2>/dev/null || git checkout master
        git pull origin "$(git symbolic-ref --short HEAD)"
        git checkout -b "$VERSION_BRANCH"
      fi
    fi
  fi
fi

# -----------------------------
# Update VERSION file (only if needed)
# -----------------------------
if [ "$UPDATE_VERSION_FILE" = true ]; then
  echo "📝 Updating VERSION file: $CURRENT_VERSION → $VERSION"
  echo "$VERSION" > VERSION
  git add VERSION
fi

# -----------------------------
# Update cargo-generate.toml branch field
# -----------------------------
if [ -f "cargo-generate.toml" ]; then
  NEEDS_UPDATE=false
  
  # Check if branch field needs updating
  if grep -q "^branch = " cargo-generate.toml; then
    CURRENT_BRANCH_VALUE=$(grep "^branch = " cargo-generate.toml | sed 's/branch = "\(.*\)"/\1/')
    if [ "$CURRENT_BRANCH_VALUE" != "$VERSION_BRANCH" ]; then
      NEEDS_UPDATE=true
      echo "📝 Updating cargo-generate.toml: branch = \"$CURRENT_BRANCH_VALUE\" → \"$VERSION_BRANCH\""
    fi
  else
    NEEDS_UPDATE=true
    echo "📝 Adding branch field to cargo-generate.toml: branch = \"$VERSION_BRANCH\""
  fi
  
  if [ "$NEEDS_UPDATE" = true ]; then
    if grep -q "^branch = " cargo-generate.toml; then
      # Update existing branch field
      if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/^branch = .*/branch = \"$VERSION_BRANCH\"/" cargo-generate.toml
      else
        sed -i "s/^branch = .*/branch = \"$VERSION_BRANCH\"/" cargo-generate.toml
      fi
    else
      # Add branch field after cargo_generate_version
      if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "/^cargo_generate_version = /a\\
branch = \"$VERSION_BRANCH\"" cargo-generate.toml
      else
        sed -i "/^cargo_generate_version = /a\\branch = \"$VERSION_BRANCH\"" cargo-generate.toml
      fi
    fi
    
    git add cargo-generate.toml
  else
    echo "✅ cargo-generate.toml already has correct branch"
  fi
fi

# -----------------------------
# Commit if needed
# -----------------------------
if ! git diff --cached --quiet; then
  COMMIT_MSG="chore(release): prepare release $VERSION"
  
  if [ "$UPDATE_VERSION_FILE" = true ] && [ "$NEEDS_UPDATE" = true ]; then
    COMMIT_MSG="chore(release): bump version to $VERSION

- Updated VERSION file to $VERSION
- Updated cargo-generate.toml branch to $VERSION_BRANCH"
  elif [ "$UPDATE_VERSION_FILE" = true ]; then
    COMMIT_MSG="chore(release): bump version to $VERSION"
  elif [ "$NEEDS_UPDATE" = true ]; then
    COMMIT_MSG="chore(release): update cargo-generate.toml branch to $VERSION_BRANCH"
  fi
  
  echo "💾 Committing changes..."
  git commit -m "$COMMIT_MSG"
else
  echo "✅ No file changes needed"
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
  if [ "$FORCE_RELEASE" = true ] || confirm "Delete and recreate remote tag '$VERSION_TAG'?"; then
    echo "🗑  Deleting remote tag: $VERSION_TAG"
    git push origin ":refs/tags/$VERSION_TAG"
  else
    echo "❌ Tag already exists"
    exit 1
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
echo "✅ Release $VERSION completed!"
echo ""
echo "📦 Install command:"
echo "   cargo generate --git $(git config --get remote.origin.url) --branch $VERSION_BRANCH --name myapp"
echo ""
echo "📌 Next steps:"
if [ "$UPDATE_VERSION_FILE" = false ]; then
  echo "   1. Create/update GitHub release for tag '$VERSION_TAG'"
  echo "   2. For next release, update VERSION file then run ./release.sh"
else
  echo "   1. Create GitHub release from tag '$VERSION_TAG'"
  echo "   2. For next release:"
  suggest_next_versions "$VERSION"
  echo "      Then run: ./release.sh"
fi