local env = {
  name = "santoku-socket",
  version = "0.0.8-1",
  license = "MIT",
  public = true,
  dependencies = {
    "lua == 5.1",
    "santoku >= 0.0.328-1",
    "santoku-system >= 0.0.63-1",
    "luasocket >= 3.1.0-1",
  },
}

env.homepage = "https://github.com/birchpointswe/lua-" .. env.name
env.tarball = env.name .. "-" .. env.version .. ".tar.gz"
env.download = env.homepage .. "/releases/download/" .. env.version .. "/" .. env.tarball

return { env = env, }
