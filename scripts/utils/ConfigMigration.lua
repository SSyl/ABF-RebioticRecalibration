--[[
============================================================================
ConfigMigration - Automatic Config File Migration (Patching Approach)
============================================================================

Handles config versioning and migration when new options are added.
- If no config.lua exists, copies from config.defaults.lua
- If config.lua exists with missing fields, PATCHES them in (preserves user's file)
- Missing fields: inserts just "Key = value,"
- Missing sections: copies full section block from defaults (with comments)

API:
- EnsureConfig(modRoot) -> boolean, string (success, error message)
]]

local ConfigMigration = {}

-- Current config version - increment when adding new options
local CURRENT_VERSION = 2

-- ============================================================
-- FILE I/O HELPERS
-- ============================================================

local function FileExists(path)
    local file = io.open(path, "r")
    if file then
        file:close()
        return true
    end
    return false
end

local function ReadFile(path)
    local file = io.open(path, "r")
    if not file then
        return nil, "Could not open file: " .. path
    end
    local content = file:read("*all")
    file:close()
    return content
end

local function WriteFile(path, content)
    local file = io.open(path, "w")
    if not file then
        return false, "Could not write file: " .. path
    end
    file:write(content)
    file:close()
    return true
end

local function CopyFile(source, dest)
    local content, err = ReadFile(source)
    if not content then
        return false, err
    end
    return WriteFile(dest, content)
end

local function GetBackupPath(configPath)
    local timestamp = os.date("%Y-%m-%d_%H%M%S")
    return configPath .. "." .. timestamp .. ".backup"
end

-- ============================================================
-- DEEP DIFF - Find missing paths
-- ============================================================

-- Returns a list of {path = "A.B.C", value = defaultValue, isSection = bool}
local function DeepDiff(defaults, userConfig, currentPath, results)
    results = results or {}
    currentPath = currentPath or ""

    for key, defaultValue in pairs(defaults) do
        -- Skip ConfigVersion - handled separately
        if key == "ConfigVersion" then
            goto continue
        end

        local fullPath = currentPath == "" and key or (currentPath .. "." .. key)
        local userValue = userConfig and userConfig[key]

        if userValue == nil then
            -- Missing in user config
            local isSection = type(defaultValue) == "table" and currentPath == ""
            table.insert(results, {
                path = fullPath,
                key = key,
                value = defaultValue,
                isSection = isSection,
                parentPath = currentPath,
            })
        elseif type(defaultValue) == "table" and type(userValue) == "table" then
            -- Both are tables, recurse
            DeepDiff(defaultValue, userValue, fullPath, results)
        end
        -- If both have values (even if different), user's value wins - no action needed

        ::continue::
    end

    return results
end

-- ============================================================
-- TEXT PARSING - Find locations in config text
-- ============================================================

-- Detect indentation style from a line
local function GetIndentation(line)
    return line:match("^(%s*)") or ""
end

-- Check if a line is just a comment or whitespace
local function IsCommentOrEmpty(line)
    local trimmed = line:match("^%s*(.-)%s*$")
    return trimmed == "" or trimmed:sub(1, 2) == "--"
end

-- Find the line number where a section starts (e.g., "    SectionName = {")
-- Returns lineNum, indentation
local function FindSectionStart(lines, sectionName)
    local pattern = "^(%s*)" .. sectionName .. "%s*=%s*{"
    for i, line in ipairs(lines) do
        local indent = line:match(pattern)
        if indent then
            return i, indent
        end
    end
    return nil, nil
end

-- Find the closing brace for a section that starts at startLine
-- Returns the line number of the closing }
local function FindSectionEnd(lines, startLine)
    local braceLevel = 0
    local started = false

    for i = startLine, #lines do
        local line = lines[i]

        -- Count braces (simplified - doesn't handle braces in strings/comments perfectly)
        for char in line:gmatch("[{}]") do
            if char == "{" then
                braceLevel = braceLevel + 1
                started = true
            elseif char == "}" then
                braceLevel = braceLevel - 1
            end
        end

        if started and braceLevel == 0 then
            return i
        end
    end

    return nil
end

-- Find insertion point for a new field in a section
-- Returns lineNum (insert BEFORE this line), indentation to use
local function FindFieldInsertionPoint(lines, parentPath)
    local parts = {}
    for part in parentPath:gmatch("[^%.]+") do
        table.insert(parts, part)
    end

    -- Navigate to the deepest section
    local currentLine = 1
    local currentIndent = ""

    for _, sectionName in ipairs(parts) do
        local startLine, indent = FindSectionStart(lines, sectionName)
        if not startLine or startLine < currentLine then
            -- Try finding it after our current position
            for i = currentLine, #lines do
                local line = lines[i]
                local foundIndent = line:match("^(%s*)" .. sectionName .. "%s*=%s*{")
                if foundIndent then
                    startLine = i
                    indent = foundIndent
                    break
                end
            end
        end

        if not startLine then
            return nil, nil, "Could not find section: " .. sectionName
        end

        currentLine = startLine
        currentIndent = indent
    end

    -- Find the end of this section
    local endLine = FindSectionEnd(lines, currentLine)
    if not endLine then
        return nil, nil, "Could not find end of section: " .. parentPath
    end

    -- Insert point is just before the closing brace
    -- Indentation should be one level deeper than the section
    local fieldIndent = currentIndent .. "    "

    return endLine, fieldIndent, nil
end

-- Find where to insert a new top-level section
-- We insert before DebugFlags section, or at end if not found
local function FindSectionInsertionPoint(lines)
    -- Look for DebugFlags section
    local debugStart = FindSectionStart(lines, "DebugFlags")
    if debugStart then
        -- Find the comment block above DebugFlags (DEBUG FLAGS header)
        local insertLine = debugStart
        for i = debugStart - 1, 1, -1 do
            local line = lines[i]
            if line:match("^%s*$") then
                -- Empty line, keep going up
                insertLine = i
            elseif line:match("^%s*%-%-") then
                -- Comment line, this might be the header
                insertLine = i
            else
                -- Found a non-comment, non-empty line - stop
                break
            end
        end
        return insertLine
    end

    -- No DebugFlags found, insert before final closing brace
    for i = #lines, 1, -1 do
        if lines[i]:match("^}") then
            return i
        end
    end

    return #lines
end

-- ============================================================
-- SECTION EXTRACTION - Get full section from defaults
-- ============================================================

-- Extract a complete section block from defaults text, including header comments
local function ExtractSectionFromDefaults(defaultsText, sectionName)
    local lines = {}
    for line in defaultsText:gmatch("([^\n]*)\n?") do
        table.insert(lines, line)
    end

    -- Find section start
    local startLine, indent = FindSectionStart(lines, sectionName)
    if not startLine then
        return nil, "Section not found: " .. sectionName
    end

    -- Find section end
    local endLine = FindSectionEnd(lines, startLine)
    if not endLine then
        return nil, "Could not find end of section: " .. sectionName
    end

    -- Include header comments above the section
    local headerStart = startLine
    for i = startLine - 1, 1, -1 do
        local line = lines[i]
        if line:match("^%s*%-%-") then
            -- Comment line, include it
            headerStart = i
        elseif line:match("^%s*$") then
            -- Empty line, include it and keep going
            headerStart = i
        else
            -- Found actual code, stop
            break
        end
    end

    -- Don't include category headers (####) - just section headers (====)
    for i = headerStart, startLine - 1 do
        if lines[i]:match("####") then
            -- Skip entire category header block until we hit ==== or non-comment
            headerStart = i + 1
            while headerStart <= startLine - 1 do
                local line = lines[headerStart]
                if line:match("====") then
                    break
                elseif line:match("^%s*%-%-") or line:match("^%s*$") then
                    headerStart = headerStart + 1
                else
                    break
                end
            end
            break
        end
    end

    -- Extract the lines
    local extracted = {}
    for i = headerStart, endLine do
        table.insert(extracted, lines[i])
    end

    return table.concat(extracted, "\n"), nil
end

-- ============================================================
-- VALUE FORMATTING
-- ============================================================

local function FormatValue(value, indent)
    local t = type(value)
    if t == "boolean" then
        return tostring(value)
    elseif t == "number" then
        return tostring(value)
    elseif t == "string" then
        -- Escape special characters
        local escaped = value:gsub("\\", "\\\\"):gsub("\"", "\\\"")
        return "\"" .. escaped .. "\""
    elseif t == "table" then
        -- Simple inline table for small tables (like colors)
        local parts = {}
        local keys = {}
        for k in pairs(value) do
            table.insert(keys, k)
        end
        table.sort(keys)

        local isSimple = true
        for _, k in ipairs(keys) do
            if type(value[k]) == "table" then
                isSimple = false
                break
            end
        end

        if isSimple and #keys <= 4 then
            -- Inline format: { R = 255, G = 128, B = 0 }
            for _, k in ipairs(keys) do
                table.insert(parts, k .. " = " .. FormatValue(value[k], indent))
            end
            return "{ " .. table.concat(parts, ", ") .. " }"
        else
            -- Multi-line format
            local innerIndent = indent .. "    "
            local lines = {"{"}
            for _, k in ipairs(keys) do
                table.insert(lines, innerIndent .. k .. " = " .. FormatValue(value[k], innerIndent) .. ",")
            end
            table.insert(lines, indent .. "}")
            return table.concat(lines, "\n")
        end
    else
        return "nil"
    end
end

-- ============================================================
-- PATCHING LOGIC
-- ============================================================

local function PatchConfig(userText, defaultsText, missingItems)
    local lines = {}
    for line in userText:gmatch("([^\n]*)\n?") do
        table.insert(lines, line)
    end

    -- Sort missing items: sections first (to avoid line number shifts affecting field insertions)
    -- Actually, process fields first, then sections at the end
    local fields = {}
    local sections = {}

    for _, item in ipairs(missingItems) do
        if item.isSection then
            table.insert(sections, item)
        else
            table.insert(fields, item)
        end
    end

    -- Process fields (insert from bottom to top to preserve line numbers)
    -- First, collect all insertions with their line numbers
    local insertions = {}

    for _, item in ipairs(fields) do
        local insertLine, indent, err = FindFieldInsertionPoint(lines, item.parentPath)
        if insertLine then
            local formattedValue = FormatValue(item.value, indent)
            local newLine = indent .. item.key .. " = " .. formattedValue .. ","
            table.insert(insertions, {line = insertLine, content = newLine})
        end
    end

    -- Sort insertions by line number descending (so we insert from bottom to top)
    table.sort(insertions, function(a, b) return a.line > b.line end)

    -- Perform field insertions
    for _, ins in ipairs(insertions) do
        table.insert(lines, ins.line, ins.content)
    end

    -- Process sections (insert at the section insertion point)
    if #sections > 0 then
        local sectionInsertPoint = FindSectionInsertionPoint(lines)

        -- Insert sections in reverse order so they appear in correct order
        for i = #sections, 1, -1 do
            local item = sections[i]
            local sectionText, err = ExtractSectionFromDefaults(defaultsText, item.key)
            if sectionText then
                -- Add blank line before section
                local sectionLines = {""}
                for line in sectionText:gmatch("([^\n]*)\n?") do
                    table.insert(sectionLines, line)
                end

                -- Insert all section lines
                for j = #sectionLines, 1, -1 do
                    table.insert(lines, sectionInsertPoint, sectionLines[j])
                end
            end
        end
    end

    return table.concat(lines, "\n")
end

-- ============================================================
-- MAIN ENTRY POINT
-- ============================================================

function ConfigMigration.EnsureConfig(modRoot)
    local configPath = modRoot .. "/config.lua"
    local defaultsPath = modRoot .. "/scripts/config.defaults.lua"

    -- Check if defaults exist
    if not FileExists(defaultsPath) then
        return false, "config.defaults.lua not found at: " .. defaultsPath
    end

    -- If no config.lua, copy from defaults (preserves all comments)
    if not FileExists(configPath) then
        local ok, err = CopyFile(defaultsPath, configPath)
        if not ok then
            return false, "Failed to create config.lua: " .. (err or "unknown error")
        end
        return true, "Created config.lua from defaults"
    end

    -- Load defaults
    local loadDefaults, defaultsErr = loadfile(defaultsPath)
    if not loadDefaults then
        return false, "Failed to load defaults: " .. (defaultsErr or "unknown error")
    end

    local okDefaults, defaults = pcall(loadDefaults)
    if not okDefaults then
        return false, "Failed to execute defaults: " .. tostring(defaults)
    end

    -- Load user config as data
    local loadUser, userErr = loadfile(configPath)
    if not loadUser then
        -- User config has syntax errors - backup and replace
        local backupPath = GetBackupPath(configPath)
        CopyFile(configPath, backupPath)
        CopyFile(defaultsPath, configPath)
        return true, "User config had syntax errors, backed up to config.lua.backup and reset to defaults"
    end

    local okUser, userConfig = pcall(loadUser)
    if not okUser or type(userConfig) ~= "table" then
        -- User config errors on execution or returned non-table (empty file)
        local backupPath = GetBackupPath(configPath)
        CopyFile(configPath, backupPath)
        CopyFile(defaultsPath, configPath)
        return true, "User config was invalid, backed up to config.lua.backup and reset to defaults"
    end

    -- Check versions
    local userVersion = userConfig.ConfigVersion or 0
    local defaultVersion = defaults.ConfigVersion or CURRENT_VERSION

    if userVersion >= defaultVersion then
        -- Config is current, no migration needed
        return true, nil
    end

    -- Find missing items
    local missingItems = DeepDiff(defaults, userConfig)

    if #missingItems == 0 then
        -- No missing items, just update version
        local userText = ReadFile(configPath)
        if userText then
            -- Update ConfigVersion in text
            local newText = userText:gsub(
                "(ConfigVersion%s*=%s*)%d+",
                "%1" .. defaultVersion
            )
            -- If ConfigVersion wasn't found, add it
            if not newText:find("ConfigVersion") then
                newText = newText:gsub(
                    "^(return%s*{)",
                    "%1\n    ConfigVersion = " .. defaultVersion .. ","
                )
            end
            WriteFile(configPath, newText)
        end
        return true, string.format("Updated config version from %d to %d", userVersion, defaultVersion)
    end

    -- Read files as text for patching
    local userText = ReadFile(configPath)
    local defaultsText = ReadFile(defaultsPath)

    if not userText or not defaultsText then
        return false, "Failed to read config files for patching"
    end

    -- Backup before patching
    local backupPath = GetBackupPath(configPath)
    CopyFile(configPath, backupPath)

    -- Patch the config
    local patchedText = PatchConfig(userText, defaultsText, missingItems)

    -- Update ConfigVersion in patched text
    local versionUpdated = false
    patchedText, versionUpdated = patchedText:gsub(
        "(ConfigVersion%s*=%s*)%d+",
        "%1" .. defaultVersion
    )

    -- If ConfigVersion wasn't found, add it after "return {"
    if versionUpdated == 0 then
        patchedText = patchedText:gsub(
            "^(return%s*{)",
            "%1\n    ConfigVersion = " .. defaultVersion .. ","
        )
    end

    -- Write patched config
    local ok, err = WriteFile(configPath, patchedText)
    if not ok then
        -- Restore backup
        CopyFile(backupPath, configPath)
        return false, "Failed to write patched config: " .. (err or "unknown error")
    end

    return true, string.format("Migrated config from version %d to %d (%d items added)",
        userVersion, defaultVersion, #missingItems)
end

return ConfigMigration
