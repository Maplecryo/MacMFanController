#!/bin/zsh
set -u

script_dir="${0:A:h}"
source_app="$script_dir/MacMFanController.app"
install_app="/Applications/Mac M Fan Controller.app"
formula="leaperone/smctl/smctl"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

fail() {
    osascript -e "display dialog \"$1\" with title \"Mac M Fan Controller\" buttons {\"OK\"} with icon stop" >/dev/null
    exit 1
}

if [[ "$(uname -s)" != "Darwin" ]]; then
    fail "This installer only runs on macOS."
fi

if [[ "$(uname -m)" != "arm64" ]]; then
    fail "This app is built for Apple Silicon Macs (M-series chips)."
fi

if [[ ! -d "$source_app" ]]; then
    fail "MacMFanController.app must be next to this installer."
fi

echo "Mac M Fan Controller installer"
echo

brew_path=""
for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -x "$candidate" ]]; then
        brew_path="$candidate"
        break
    fi
done

smctl_path=""
for candidate in /opt/homebrew/bin/smctl /usr/local/bin/smctl /usr/bin/smctl; do
    if [[ -x "$candidate" ]]; then
        smctl_path="$candidate"
        break
    fi
done

if [[ -z "$smctl_path" ]]; then
    if [[ -z "$brew_path" ]]; then
        open "https://brew.sh"
        fail "Homebrew is needed for the fan-control backend. I opened the Homebrew website so it can be installed first, then run this installer again."
    fi

    echo "Installing the fan-control backend..."
    "$brew_path" install "$formula" || fail "The backend could not be installed. Check the Terminal window for details and run this installer again."
    smctl_path="$(command -v smctl || true)"
    [[ -n "$smctl_path" ]] || smctl_path="/opt/homebrew/bin/smctl"
fi

echo "Installing the app in /Applications..."
/usr/bin/ditto "$source_app" "$install_app" || fail "The app could not be copied to /Applications."

echo "Setting up the fan-control service..."
if ! "$smctl_path" sensors >/dev/null 2>&1; then
    /usr/bin/sudo "$smctl_path" daemon install || fail "The fan-control service could not be set up. Check the Terminal window for details."
fi

/usr/bin/open "$install_app"
osascript -e 'display dialog "Installation is complete. The app is now in your menu bar." with title "Mac M Fan Controller" buttons {"Done"} with icon note' >/dev/null
