cask "cliproxybar" do
  version "0.4.8"
  sha256 "d61175f6fcfef4f47fba39018655a86a4369950da36a5c57555c5bd73f38f82e"

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
