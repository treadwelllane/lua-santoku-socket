local env = {
  name = "santoku-socket",
  version = "0.0.5-1",
  license = "MIT",
  public = true,
  dependencies = {
    "lua == 5.1",
    "santoku >= 0.0.318-1",
    "santoku-system >= 0.0.61-1",
    "luasocket >= 3.1.0-1",
  },
}

env.homepage = "https://github.com/treadwelllane/lua-" .. env.name
env.tarball = env.name .. "-" .. env.version .. ".tar.gz"
env.download = env.homepage .. "/releases/download/" .. env.version .. "/" .. env.tarball

return { env = env, }
