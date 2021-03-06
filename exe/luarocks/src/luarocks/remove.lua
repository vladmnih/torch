
--- Module implementing the LuaRocks "remove" command.
-- Uninstalls rocks.
module("luarocks.remove", package.seeall)

local search = require("luarocks.search")
local deps = require("luarocks.deps")
local fetch = require("luarocks.fetch")
local repos = require("luarocks.repos")
local path = require("luarocks.path")
local util = require("luarocks.util")
local cfg = require("luarocks.cfg")
local manif = require("luarocks.manif")
local fs = require("luarocks.fs")

help_summary = "Uninstall a rock."
help_arguments = "[--force] <name> [<version>]"
help = [[
Argument is the name of a rock to be uninstalled.
If a version is not given, try to remove all versions at once.
Will only perform the removal if it does not break dependencies.
To override this check and force the removal, use --force.
]]

--- Obtain a list of packages that depend on the given set of packages
-- (where all packages of the set are versions of one program).
-- @param name string: the name of a program
-- @param versions array of string: the versions to be deleted.
-- @return array of string: an empty table if no packages depend on any
-- of the given list, or an array of strings in "name/version" format.
local function check_dependents(name, versions, deps_mode)
   local dependents = {}
   local blacklist = {}
   blacklist[name] = {}
   for version, _ in pairs(versions) do
      blacklist[name][version] = true
   end
   local local_rocks = {}
   local query_all = search.make_query("")
   query_all.exact_name = false
   search.manifest_search(local_rocks, cfg.rocks_dir, query_all)
   local_rocks[name] = nil
   for rock_name, rock_versions in pairs(local_rocks) do
      for rock_version, _ in pairs(rock_versions) do
         local rockspec, err = fetch.load_rockspec(path.rockspec_file(rock_name, rock_version))
         if rockspec then
            local _, missing = deps.match_deps(rockspec, blacklist, deps_mode)
            if missing[name] then
               table.insert(dependents, { name = rock_name, version = rock_version })
            end
         end
      end
   end
   return dependents
end

--- Delete given versions of a program.
-- @param name string: the name of a program
-- @param versions array of string: the versions to be deleted.
-- @return boolean or (nil, string): true on success or nil and an error message.
local function delete_versions(name, versions) 

   for version, _ in pairs(versions) do
      util.printout("Removing "..name.." "..version.."...")
      local ok, err = repos.delete_version(name, version)
      if not ok then return nil, err end
   end
   
   return true
end

--- Driver function for the "remove" command.
-- @param name string: name of a rock. If a version is given, refer to
-- a specific version; otherwise, try to remove all versions.
-- @param version string: When passing a package name, a version number
-- may also be given.
-- @return boolean or (nil, string): True if removal was
-- successful, nil and an error message otherwise.
function run(...)
   local flags, name, version = util.parse_flags(...)
   
   if type(name) ~= "string" then
      return nil, "Argument missing, see help."
   end
   
   local deps_mode = flags["deps-mode"] or cfg.deps_mode
   
   local ok, err = fs.check_command_permissions(flags)
   if not ok then return nil, err end
   
   local rock_type = name:match("%.(rock)$") or name:match("%.(rockspec)$")
   local filename = name
   if rock_type then
      name, version = path.parse_name(filename)
      if not name then return nil, "Invalid "..rock_type.." filename: "..filename end
   end

   local results = {}
   search.manifest_search(results, cfg.rocks_dir, search.make_query(name, version))

   local versions = results[name]
   if not versions then
      return nil, "Could not find rock '"..name..(version and " "..version or "").."' in local tree."
   else
      local version = next(versions)
      local second = next(versions, version)
      
      util.printout("Checking stability of dependencies on the absence of")
      util.printout(name.." "..table.concat(util.keys(versions), ", ").."...")
      util.printout()
      
      local dependents = check_dependents(name, versions, deps_mode)
      
      if #dependents == 0 or flags["force"] then
         if #dependents > 0 then
            util.printerr("The following packages may be broken by this forced removal:")
            for _, dependent in ipairs(dependents) do
               util.printerr(dependent.name.." "..dependent.version)
            end
            util.printerr()
         end
         local ok, err = delete_versions(name, versions)
         if not ok then return nil, err end
         ok, err = manif.make_manifest(cfg.rocks_dir, deps_mode)
         if not ok then return nil, err end
      else
         if not second then
            util.printerr("Will not remove "..name.." "..version..".")
            util.printerr("Removing it would break dependencies for: ")
         else
            util.printerr("Will not remove all versions of "..name..".")
            util.printerr("Removing them would break dependencies for: ")
         end
         for _, dependent in ipairs(dependents) do
            util.printerr(dependent.name.." "..dependent.version)
         end
         util.printerr()
         util.printerr("Use --force to force removal (warning: this may break modules).")
         return nil, "Failed removing."
      end
   end
   util.printout("Removal successful.")
   return true
end
