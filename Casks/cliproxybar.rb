cask "cliproxybar" do
  version "0.4.2"
  sha256 "91bea4cd6898eb26ea49fbc86fb78bbbb601f9c8acdc31ba95bb0add3fead298"

  url "https://github.com/darfink/cliproxybar/releases/download/v#{version}/CLIProxyBar-#{version}-macOS-universal.zip"
  name "CLIProxyBar"
  desc "Menu bar quotas and usage for CLIProxyAPI"
  homepage "https://github.com/darfink/cliproxybar"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: :sonoma

  app "CLIProxyBar.app"

  zap trash: [
    "~/Library/Application Support/CLIProxyBar",
    "~/Library/Caches/io.github.darfink.CLIProxyBar",
    "~/Library/Preferences/io.github.darfink.CLIProxyBar.plist",
  ]
end
