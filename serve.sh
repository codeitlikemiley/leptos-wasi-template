#!/usr/bin/env bash
set -euo pipefail

# -----------------------------
# RELEASE SCRIPT FOR CARGO-GENERATE TEMPLATES
# Branches: 0.1.3 (no v prefix) - for cargo generate
# Tags: v0.1.3 (with v prefix) - for GitHub releases
# -----------------------------

confirm() {
  read -r -p "$1 (y/N): " response
  case "$response" in
    [yY][eE][sS]|[yY]) true ;;
    *) false ;;
  esac
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

echo "🎯 Release Plan:"
echo "   Version: $VERSION"
echo "   Branch:  $VERSION_BRANCH (for cargo generate)"
echo "   Tag:     $VERSION_TAG (for GitHub releases)"
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
# Fetch latest changes
# -----------------------------
echo "📥 Fetching latest changes..."
git fetch origin --tags --prune

# -----------------------------
# Handle the version branch
# -----------------------------
if [ "$CURRENT_BRANCH" = "$VERSION_BRANCH" ]; then
  echo "✅ Already on version branch '$VERSION_BRANCH'"
  
  # Sync with remote if it exists
  if git show-ref --verify --quiet "refs/remotes/origin/$VERSION_BRANCH"; then
    echo "📦 Pulling latest changes from origin/$VERSION_BRANCH..."
    git pull origin "$VERSION_BRANCH"
  fi
  
elif git show-ref --verify --quiet "refs/heads/$VERSION_BRANCH"; then
  echo "ℹ️  Version branch '$VERSION_BRANCH' exists locally"
  if confirm "Switch to existing branch '$VERSION_BRANCH'?"; then
    git checkout "$VERSION_BRANCH"
    
    # Sync with remote if it exists
    if git show-ref --verify --quiet "refs/remotes/origin/$VERSION_BRANCH"; then
      echo "📦 Pulling latest changes from origin/$VERSION_BRANCH..."
      git pull origin "$VERSION_BRANCH"
    fi
  else
    echo "❌ Release aborted"
    exit 1
  fi
  
else
  # Create new version branch
  echo "🌿 Version branch '$VERSION_BRANCH' doesn't exist"
  
  # Determine base branch
  if [[ "$CURRENT_BRANCH" == "main" || "$CURRENT_BRANCH" == "master" ]]; then
    BASE_BRANCH="$CURRENT_BRANCH"
  else
    echo "⚠️  You're not on main/master branch"
    if confirm "Create version branch from current branch '$CURRENT_BRANCH'?"; then
      BASE_BRANCH="$CURRENT_BRANCH"
    elif confirm "Switch to main branch first?"; then
      git checkout main 2>/dev/null || git checkout master
      BASE_BRANCH=$(git symbolic-ref --short HEAD)
    else
      echo "❌ Release aborted"
      exit 1
    fi
  fi
  
  echo "🌿 Creating version branch '$VERSION_BRANCH' from '$BASE_BRANCH'..."
  git checkout -b "$VERSION_BRANCH"
fi

# -----------------------------
# Update VERSION file
# -----------------------------
if [ ! -f VERSION ]; then
  echo "0.0.0" > VERSION
fi

PREV_VERSION=$(cat VERSION || echo "0.0.0")

if [ "$PREV_VERSION" != "$VERSION" ]; then
  echo "📝 Updating VERSION: $PREV_VERSION → $VERSION"
  echo "$VERSION" > VERSION
  git add VERSION
fi

# -----------------------------
# Update cargo-generate.toml
# -----------------------------
if [ -f "cargo-generate.toml" ]; then
  echo "📝 Updating cargo-generate.toml to use branch '$VERSION_BRANCH'"
  
  # Create temp file with updated content
  cat > cargo-generate.toml.tmp << EOF
[template]
cargo_generate_version = ">=0.15.0"
branch = "$VERSION_BRANCH"
exclude = [
    "public/**/*.ico",
]

[placeholders.description]
prompt = "Enter a short description for your project"
default = "A Leptos application running as a WASI Component"

[placeholders.port]
prompt = "Which port should the server run on?"
default = "8080"
regex = "^[0-9]{4,5}$"

[placeholders.component_outdir]
prompt = "Where to output your WASI component"
default = "target/server"

[copy]
"public/**/*.ico" = "public/"
EOF
  
  mv cargo-generate.toml.tmp cargo-generate.toml
  git add cargo-generate.toml
fi

# -----------------------------
# Commit changes if any
# -----------------------------
if ! git diff --cached --quiet; then
  echo "💾 Committing version changes..."
  git commit -m "chore(release): prepare version $VERSION"
else
  echo "ℹ️  No changes to commit"
fi

# -----------------------------
# Push the version branch
# -----------------------------
echo "⬆️  Pushing branch '$VERSION_BRANCH'..."
if git show-ref --verify --quiet "refs/remotes/origin/$VERSION_BRANCH"; then
  git push origin "$VERSION_BRANCH"
else
  git push --set-upstream origin "$VERSION_BRANCH"
fi

# -----------------------------
# Handle the tag
# -----------------------------
# Delete existing local tag if present
if git rev-parse "$VERSION_TAG" >/dev/null 2>&1; then
  echo "🗑  Deleting existing local tag: $VERSION_TAG"
  git tag -d "$VERSION_TAG"
fi

# Check for existing remote tag
if git ls-remote --tags origin | grep -q "refs/tags/$VERSION_TAG"; then
  echo "⚠️  Remote tag '$VERSION_TAG' already exists"
  if confirm "Delete and recreate remote tag?"; then
    echo "🗑  Deleting remote tag: $VERSION_TAG"
    git push origin ":refs/tags/$VERSION_TAG"
  else
    echo "❌ Cannot proceed with existing tag"
    exit 1
  fi
fi

# Create new tag
echo "✨ Creating tag: $VERSION_TAG"
git tag -a "$VERSION_TAG" -m "Release $VERSION

Template installation:
- Via branch: cargo generate --git $(git config --get remote.origin.url) --branch $VERSION_BRANCH
- Via tag: cargo generate --git $(git config --get remote.origin.url) --tag $VERSION_TAG"

# Push tag
echo "⬆️  Pushing tag '$VERSION_TAG'..."
git push origin "$VERSION_TAG"

# -----------------------------
# Success!
# -----------------------------
echo ""
echo "✅ Release $VERSION completed successfully!"
echo ""
echo "📋 Summary:"
echo "   • Branch '$VERSION_BRANCH' created and pushed (for cargo-generate)"
echo "   • Tag '$VERSION_TAG' created and pushed (for GitHub releases)"
echo ""
echo "📦 Users can now install with:"
echo "   cargo generate --git $(git config --get remote.origin.url) --branch $VERSION_BRANCH --name myapp"
echo ""
echo "📌 Next steps:"
echo "   1. Create GitHub release from tag '$VERSION_TAG'"
echo "   2. Test the template installation"
echo "   3. Update README if needed"