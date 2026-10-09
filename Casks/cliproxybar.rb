cask "cliproxybar" do
  version "0.4.0"
  sha256 "198eb2a22952b9503918215723300238583ec1ed82ab3b7489bd2b982ca7bf43"

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
