cask "cliproxybar" do
  version "0.4.1"
  sha256 "53843f6ab89adb0657a7fc005a2ecbe185afcc52aefb1cc2c5542f098b85677d"

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
