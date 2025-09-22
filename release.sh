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
# Returns: 0 if v1 > v2, 1 if v1 < v2, 2 if equal
version_compare() {
  local v1="$1"
  local v2="$2"
  
  IFS='.' read -ra V1_PARTS <<< "$v1"
  IFS='.' read -ra V2_PARTS <<< "$v2"
  
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
VERSION_SOURCE=""

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
    FORCE_RELEASE=true
    if [ -f VERSION ]; then
      VERSION=$(cat VERSION | tr -d '[:space:]')
      VERSION_SOURCE="file"
      echo "📊 Using version from VERSION file: $VERSION (--force)"
    else
      echo "❌ No VERSION file found!"
      exit 1
    fi
  else
    VERSION="$1"
    VERSION_SOURCE="argument"
  fi
elif [ $# -eq 2 ] && [ "$2" = "--force" ]; then
  VERSION="$1"
  VERSION_SOURCE="argument"
  FORCE_RELEASE=true
else
  echo "Usage: ./release.sh [version] [--force]"
  echo ""
  echo "Examples:"
  echo "  ./release.sh              # Use VERSION file"
  echo "  ./release.sh 0.1.4        # Release version 0.1.4"
  echo "  ./release.sh 0.1.3 --force # Force release 0.1.3"
  exit 1
fi

# Validate version format
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "❌ Invalid version format: $VERSION"
  echo "   Format must be: MAJOR.MINOR.PATCH (e.g., 0.1.3)"
  exit 1
fi

VERSION_BRANCH="$VERSION"
VERSION_TAG="v$VERSION"

# -----------------------------
# Check VERSION file and decide if update needed
# -----------------------------
UPDATE_VERSION_FILE=false
CURRENT_VERSION="0.0.0"

if [ -f VERSION ]; then
  CURRENT_VERSION=$(cat VERSION | tr -d '[:space:]')
  
  if [ "$VERSION_SOURCE" = "argument" ]; then
    version_compare "$VERSION" "$CURRENT_VERSION"
    COMPARE_RESULT=$?
    
    if [ $COMPARE_RESULT -eq 2 ]; then
      echo "✅ Version matches VERSION file: $VERSION"
    elif [ $COMPARE_RESULT -eq 0 ]; then
      echo "📈 Version upgrade: $CURRENT_VERSION → $VERSION"
      UPDATE_VERSION_FILE=true
    else
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
  fi
else
  echo "ℹ️  Creating VERSION file with: $VERSION"
  UPDATE_VERSION_FILE=true
fi

echo ""
echo "🎯 Release Plan:"
echo "   Version: $VERSION"
echo "   Branch:  $VERSION_BRANCH"
echo "   Tag:     $VERSION_TAG"
if [ "$UPDATE_VERSION_FILE" = true ]; then
  echo "   Update VERSION: $CURRENT_VERSION → $VERSION"
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
  
  # Check if branch exists on remote and sync
  if git show-ref --verify --quiet "refs/remotes/origin/$VERSION_BRANCH"; then
    LOCAL=$(git rev-parse HEAD)
    REMOTE=$(git rev-parse "origin/$VERSION_BRANCH")
    
    if [ "$LOCAL" != "$REMOTE" ]; then
      BEHIND=$(git rev-list --count HEAD..origin/"$VERSION_BRANCH" 2>/dev/null || echo "0")
      AHEAD=$(git rev-list --count origin/"$VERSION_BRANCH"..HEAD 2>/dev/null || echo "0")
      
      if [ "$BEHIND" -gt 0 ] && [ "$AHEAD" -gt 0 ]; then
        echo "⚠️  Branch has diverged: $AHEAD commits ahead, $BEHIND commits behind"
        if confirm "Pull and merge remote changes?"; then
          git pull origin "$VERSION_BRANCH" --rebase=false
        fi
      elif [ "$BEHIND" -gt 0 ]; then
        echo "⬇️  Branch is $BEHIND commits behind remote"
        if confirm "Pull remote changes?"; then
          git pull origin "$VERSION_BRANCH"
        fi
      elif [ "$AHEAD" -gt 0 ]; then
        echo "⬆️  Branch is $AHEAD commits ahead of remote"
        echo "   These will be pushed during release"
      fi
    else
      echo "✅ Branch is in sync with remote"
    fi
  else
    echo "ℹ️  Branch doesn't exist on remote yet"
  fi
  
else
  # Need to switch to version branch
  if git show-ref --verify --quiet "refs/heads/$VERSION_BRANCH"; then
    echo "📋 Switching to existing branch '$VERSION_BRANCH'"
    git checkout "$VERSION_BRANCH"
    
    if git show-ref --verify --quiet "refs/remotes/origin/$VERSION_BRANCH"; then
      echo "📥 Pulling latest changes..."
      git pull origin "$VERSION_BRANCH" --rebase=false
    fi
  else
    echo "🌿 Creating new version branch '$VERSION_BRANCH'"
    
    if [[ "$CURRENT_BRANCH" == "main" || "$CURRENT_BRANCH" == "master" ]]; then
      git checkout -b "$VERSION_BRANCH"
    else
      echo "⚠️  You're on '$CURRENT_BRANCH' (not main/master)"
      if confirm "Create branch from current location?"; then
        git checkout -b "$VERSION_BRANCH"
      else
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
NEEDS_CARGO_UPDATE=false

if [ -f "cargo-generate.toml" ]; then
  if grep -q "^branch = " cargo-generate.toml; then
    CURRENT_BRANCH_VALUE=$(grep "^branch = " cargo-generate.toml | sed 's/branch = "\(.*\)"/\1/')
    if [ "$CURRENT_BRANCH_VALUE" != "$VERSION_BRANCH" ]; then
      NEEDS_CARGO_UPDATE=true
      echo "📝 Updating cargo-generate.toml: branch = \"$CURRENT_BRANCH_VALUE\" → \"$VERSION_BRANCH\""
    fi
  else
    NEEDS_CARGO_UPDATE=true
    echo "📝 Adding branch field to cargo-generate.toml: branch = \"$VERSION_BRANCH\""
  fi
  
  if [ "$NEEDS_CARGO_UPDATE" = true ]; then
    if grep -q "^branch = " cargo-generate.toml; then
      if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/^branch = .*/branch = \"$VERSION_BRANCH\"/" cargo-generate.toml
      else
        sed -i "s/^branch = .*/branch = \"$VERSION_BRANCH\"/" cargo-generate.toml
      fi
    else
      if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "/^cargo_generate_version = /a\\
branch = \"$VERSION_BRANCH\"" cargo-generate.toml
      else
        sed -i "/^cargo_generate_version = /a\\branch = \"$VERSION_BRANCH\"" cargo-generate.toml
      fi
    fi
    
    git add cargo-generate.toml
  fi
fi

# -----------------------------
# Commit if needed
# -----------------------------
if ! git diff --cached --quiet; then
  COMMIT_MSG="chore(release): prepare release $VERSION"
  
  if [ "$UPDATE_VERSION_FILE" = true ] && [ "$NEEDS_CARGO_UPDATE" = true ]; then
    COMMIT_MSG="chore(release): bump version to $VERSION

- Updated VERSION file to $VERSION
- Updated cargo-generate.toml branch to $VERSION_BRANCH"
  elif [ "$UPDATE_VERSION_FILE" = true ]; then
    COMMIT_MSG="chore(release): bump version to $VERSION"
  elif [ "$NEEDS_CARGO_UPDATE" = true ]; then
    COMMIT_MSG="chore(release): update cargo-generate.toml branch to $VERSION_BRANCH"
  fi
  
  echo "💾 Committing changes..."
  git commit -m "$COMMIT_MSG"
fi

# -----------------------------
# Push branch (including any unpushed commits)
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
TAG_EXISTS_LOCAL=false
TAG_EXISTS_REMOTE=false

if git rev-parse "$VERSION_TAG" >/dev/null 2>&1; then
  TAG_EXISTS_LOCAL=true
  echo "🔍 Local tag exists: $VERSION_TAG"
fi

if git ls-remote --tags origin | grep -q "refs/tags/$VERSION_TAG"; then
  TAG_EXISTS_REMOTE=true
  echo "🔍 Remote tag exists: $VERSION_TAG"
fi

if [ "$TAG_EXISTS_LOCAL" = true ] || [ "$TAG_EXISTS_REMOTE" = true ]; then
  if [ "$FORCE_RELEASE" = true ]; then
    echo "⚠️  Force mode: recreating tag"
    RECREATE_TAG=true
  else
    if confirm "Tag '$VERSION_TAG' exists. Delete and recreate?"; then
      RECREATE_TAG=true
    else
      echo "ℹ️  Keeping existing tag"
      RECREATE_TAG=false
    fi
  fi
  
  if [ "$RECREATE_TAG" = true ]; then
    if [ "$TAG_EXISTS_LOCAL" = true ]; then
      echo "🗑  Deleting local tag: $VERSION_TAG"
      git tag -d "$VERSION_TAG"
    fi
    
    if [ "$TAG_EXISTS_REMOTE" = true ]; then
      echo "🗑  Deleting remote tag: $VERSION_TAG"
      git push origin ":refs/tags/$VERSION_TAG"
    fi
    
    echo "✨ Creating new tag: $VERSION_TAG"
    git tag -a "$VERSION_TAG" -m "Release $VERSION

cargo generate --git $(git config --get remote.origin.url) --branch $VERSION_BRANCH --name myapp"
    
    echo "⬆️  Pushing tag '$VERSION_TAG'..."
    git push origin "$VERSION_TAG"
  fi
else
  echo "✨ Creating tag: $VERSION_TAG"
  git tag -a "$VERSION_TAG" -m "Release $VERSION

cargo generate --git $(git config --get remote.origin.url) --branch $VERSION_BRANCH --name myapp"
  
  echo "⬆️  Pushing tag '$VERSION_TAG'..."
  git push origin "$VERSION_TAG"
fi

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
echo "   1. Create/update GitHub release for tag '$VERSION_TAG'"
echo "   2. For next release:"
suggest_next_versions "$VERSION"
echo "      Then run: ./release.sh"