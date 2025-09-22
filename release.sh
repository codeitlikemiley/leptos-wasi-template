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
# Handle different branch scenarios
# -----------------------------
if [ "$CURRENT_BRANCH" = "$VERSION_BRANCH" ]; then
  # SCENARIO 1: Already on the correct version branch
  echo "✅ Already on version branch '$VERSION_BRANCH'"
  
  # Check if branch exists on remote
  if git show-ref --verify --quiet "refs/remotes/origin/$VERSION_BRANCH"; then
    echo "📦 Branch exists on remote, checking for updates..."
    
    # Check if we're behind/ahead
    LOCAL_COMMIT=$(git rev-parse HEAD)
    REMOTE_COMMIT=$(git rev-parse "origin/$VERSION_BRANCH")
    
    if [ "$LOCAL_COMMIT" != "$REMOTE_COMMIT" ]; then
      BEHIND=$(git rev-list --count HEAD..origin/"$VERSION_BRANCH")
      AHEAD=$(git rev-list --count origin/"$VERSION_BRANCH"..HEAD)
      
      if [ "$BEHIND" -gt 0 ] && [ "$AHEAD" -gt 0 ]; then
        echo "⚠️  Branch has diverged: $AHEAD commits ahead, $BEHIND commits behind"
        if confirm "Pull and merge remote changes?"; then
          git pull origin "$VERSION_BRANCH" --no-rebase
        fi
      elif [ "$BEHIND" -gt 0 ]; then
        echo "⬇️  Branch is $BEHIND commits behind"
        if confirm "Pull remote changes?"; then
          git pull origin "$VERSION_BRANCH"
        fi
      elif [ "$AHEAD" -gt 0 ]; then
        echo "⬆️  Branch is $AHEAD commits ahead of remote"
      fi
    else
      echo "✅ Branch is up to date with remote"
    fi
  else
    echo "ℹ️  Branch doesn't exist on remote yet (will push later)"
  fi
  
  # Ask if they want to continue with the release from here
  if ! confirm "Continue with release from current branch '$VERSION_BRANCH'?"; then
    echo "❌ Release aborted"
    exit 1
  fi

elif [[ "$CURRENT_BRANCH" == "main" || "$CURRENT_BRANCH" == "master" ]]; then
  # SCENARIO 2: On main/master, need to create or switch to version branch
  echo "📍 On $CURRENT_BRANCH branch"
  
  # Pull latest main
  echo "📦 Updating $CURRENT_BRANCH..."
  git pull origin "$CURRENT_BRANCH"
  
  # Check if version branch exists
  if git show-ref --verify --quiet "refs/heads/$VERSION_BRANCH"; then
    echo "ℹ️  Version branch '$VERSION_BRANCH' exists locally"
    if confirm "Switch to branch '$VERSION_BRANCH'?"; then
      git checkout "$VERSION_BRANCH"
      
      # Merge main into version branch
      if confirm "Update version branch with latest from $CURRENT_BRANCH?"; then
        git merge "$CURRENT_BRANCH" --no-edit
      fi
    else
      echo "❌ Release aborted"
      exit 1
    fi
  else
    echo "🌿 Creating new version branch '$VERSION_BRANCH'..."
    git checkout -b "$VERSION_BRANCH"
  fi

else
  # SCENARIO 3: On some other branch
  echo "⚠️  You're on branch '$CURRENT_BRANCH' (not main/master or version branch)"
  
  # Check if version branch exists
  if git show-ref --verify --quiet "refs/heads/$VERSION_BRANCH"; then
    echo "ℹ️  Version branch '$VERSION_BRANCH' already exists"
    if confirm "Switch to branch '$VERSION_BRANCH'?"; then
      git checkout "$VERSION_BRANCH"
    else
      echo "❌ Release aborted"
      exit 1
    fi
  else
    echo "🌿 Version branch '$VERSION_BRANCH' doesn't exist"
    
    # Ask what to do
    echo ""
    echo "Options:"
    echo "  1) Create version branch from current branch '$CURRENT_BRANCH'"
    echo "  2) Switch to main/master first"
    echo "  3) Abort"
    
    read -r -p "Choose option (1/2/3): " option
    case "$option" in
      1)
        echo "🌿 Creating version branch from '$CURRENT_BRANCH'..."
        git checkout -b "$VERSION_BRANCH"
        ;;
      2)
        git checkout main 2>/dev/null || git checkout master
        git pull origin "$(git symbolic-ref --short HEAD)"
        echo "🌿 Creating version branch from main/master..."
        git checkout -b "$VERSION_BRANCH"
        ;;
      *)
        echo "❌ Release aborted"
        exit 1
        ;;
    esac
  fi
fi

# -----------------------------
# Now we're definitely on the version branch
# -----------------------------
CURRENT_BRANCH=$(git symbolic-ref --short HEAD)
echo ""
echo "🎯 Working on branch: $CURRENT_BRANCH"

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
elif ! git diff --quiet; then
  echo "⚠️  You have uncommitted changes"
  if confirm "Stage and commit all changes?"; then
    git add -A
    git commit -m "chore(release): prepare version $VERSION"
  fi
else
  echo "ℹ️  No changes to commit"
fi

# -----------------------------
# Push the version branch
# -----------------------------
echo ""
echo "⬆️  Pushing branch '$VERSION_BRANCH'..."
if git show-ref --verify --quiet "refs/remotes/origin/$VERSION_BRANCH"; then
  # Branch exists on remote, regular push
  git push origin "$VERSION_BRANCH"
else
  # New branch, set upstream
  git push --set-upstream origin "$VERSION_BRANCH"
fi

# -----------------------------
# Handle the tag
# -----------------------------
echo ""
echo "🏷️  Handling tag '$VERSION_TAG'..."

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
    echo "⚠️  Keeping existing tag"
    echo "ℹ️  Skipping tag creation"
  fi
fi

# Create new tag (only if we deleted or it didn't exist)
if ! git rev-parse "$VERSION_TAG" >/dev/null 2>&1; then
  echo "✨ Creating tag: $VERSION_TAG"
  git tag -a "$VERSION_TAG" -m "Release $VERSION

Template installation:
- Via branch: cargo generate --git $(git config --get remote.origin.url) --branch $VERSION_BRANCH
- Via tag: cargo generate --git $(git config --get remote.origin.url) --tag $VERSION_TAG"

  # Push tag
  echo "⬆️  Pushing tag '$VERSION_TAG'..."
  git push origin "$VERSION_TAG"
fi

# -----------------------------
# Success!
# -----------------------------
echo ""
echo "✅ Release $VERSION completed successfully!"
echo ""
echo "📋 Summary:"
echo "   • Branch '$VERSION_BRANCH' pushed"
echo "   • Tag '$VERSION_TAG' created and pushed"
echo ""
echo "📦 Users can now install with:"
echo "   cargo generate --git $(git config --get remote.origin.url) --branch $VERSION_BRANCH --name myapp"
echo ""
echo "📌 Next steps:"
echo "   1. Create GitHub release from tag '$VERSION_TAG'"
echo "   2. Test the template installation"
echo "   3. Consider merging back to main if needed"