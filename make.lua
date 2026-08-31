local env = {
  name = "santoku-socket",
  version = "2.1.0-1",
  license = "MIT",
  public = true,
  dependencies = {
    "lua == 5.1",
    "santoku >= 2.0.0, < 3.0.0",
    "santoku-system >= 2.0.0, < 3.0.0",
    "luasocket >= 3.1.0-1",
    "luasec >= 1.3.2-1",
  },
}

env.homepage = "https://github.com/birchpointswe/lua-" .. env.name
env.tarball = env.name .. "-" .. env.version .. ".tar.gz"
env.download = env.homepage .. "/releases/download/" .. env.version .. "/" .. env.tarball

return { env = env, }
