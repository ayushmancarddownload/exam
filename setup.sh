#!/usr/bin/env bash
# One-shot local setup: checks Node, writes .env, installs, builds.
set -e
cd "$(dirname "$0")"

major=$(node -v 2>/dev/null | sed 's/^v//;s/\..*//' || true)
if [ -z "$major" ] || [ "$major" -lt 22 ]; then
  echo "Node 22 chahiye. Abhi: $(node -v 2>/dev/null || echo 'installed nahi')"
  echo ""
  echo "Ye chalao (ek baar):"
  echo "  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash"
  echo "Terminal band karke naya kholo, phir:"
  echo "  nvm install 22 && nvm alias default 22"
  echo "Uske baad dobara: ./setup.sh"
  exit 1
fi

if ! grep -q 'sb_publishable_' .env 2>/dev/null; then
  read -r -p "Supabase publishable key paste karo (sb_publishable_...): " KEY
  printf 'PUBLIC_SUPABASE_URL=https://wlxnxamlsqezpjsdyrah.supabase.co\nPUBLIC_SUPABASE_ANON_KEY=%s\n' "$KEY" > .env
fi

npm install
npm run build
echo ""
echo "Build ho gaya. Local me chalane ke liye: npm run dev"
