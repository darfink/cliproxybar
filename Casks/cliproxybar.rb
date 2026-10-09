cask "cliproxybar" do
  version "0.2.3"
  sha256 "98c83270832132b1f5d62a41a3095a73ef1eba73c823b255e7e17bf0eed7d091"

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
