---@class config
---@field fold_lines_after_line integer - default 30
---@field openTypeDocKeymap string|nil - default <C-P>. Set to '' to disable
---@field keys_that_open_nested_types string[] - default <C-P>. Set to '' to disable
---@field types_to_not_expand string[] - if a type is in this list, a type hint letter wont appear next to it in the main_window
---@field fallback_to_old_on_anything_but_interface_and_type boolean -- default is true

local M = {}

---@type config
M.config = {
	fold_lines_after_line = 20,
	openTypeDocKeymap = "<C-P>",
	fallback_to_old_on_anything_but_interface_and_type = true,
	keys_that_open_nested_types = { 'a', 's', 'b', 'i', 'e', 'u', 'r', 'x' },
	types_to_not_expand = {"string", "number", "boolean", "Date"}
}
---@type nil|integer
M.win_id_of_selected_key_hint = nil
M.win_ids = {}
M.listening_for_input = false
M.original_mappings = {}
M.all_keys = { M.openTypeDocKeymap }
for _, v in ipairs(M.config.keys_that_open_nested_types) do
	table.insert(M.all_keys, v)
end

vim.cmd('highlight key_hint_color guifg=#FFFFFF guibg=NONE')  -- Keyword color
vim.cmd('highlight selected_key_hint_color guifg=#BC0000 guibg=NONE')  -- Keyword color

local selected_key_hint_color_namespace = vim.api.nvim_create_namespace("selected_key_hint_color_namespace")

---@class Item
---@field lines string[]
---@field items any[]
---@field filename string
---@field win_id number
---@field start_line number
---@field end_line number

---@type Item|nil
M.main_window = nil
---@type Item|nil
M.secondary_window = nil

---@type integer[]
M.main_window_key_hint_win_ids = {}

function M.better_type_hover()
	M.open_primary_window()
end

---@param config config|nil
function M.setup(config)
	if config ~= nil then
		M.config.openTypeDocKeymap = config.openTypeDocKeymap or M.config.openTypeDocKeymap
	end
	vim.keymap.set('n', M.config.openTypeDocKeymap, M.better_type_hover)

	if config == nil then return end

	-- Override default config options
	for key, value in pairs(config) do
		M.config[key] = value
	end

	if config.keys_that_open_nested_types ~= nil then
		for _, v in ipairs(M.config.keys_that_open_nested_types) do
			table.insert(M.all_keys, v)
		end
	end
end



function M.store_mappings()
	-- vim.notify("M.store_mappings()")
	for _, key in ipairs(M.all_keys) do
		-- vim.notify("storing mapping: " .. vim.inspect(key))
		M.original_mappings[key] = vim.fn.maparg(key, 'n', false, true)
	end
end

function M.restore_mappings()
	-- vim.notify("M.restore_mappings()")
	for lhs, data in pairs(M.original_mappings) do
		-- vim.notify("Restoring key: " .. vim.inspect(lhs))
		local needs_restore = vim.tbl_count(data) > 0
		if needs_restore then vim.fn.mapset('n', false, data) end
		if not needs_restore then vim.keymap.del('n', lhs) end
	end
	M.original_mappings = {} -- Clear after restoration
end

function M.safe_delete_keymap(mode, key)
	-- Attempt to delete the keymap, and catch any errors
	local success, err = pcall(vim.api.nvim_del_keymap, mode, key)
	if success then
		-- vim.notify("safe_deleted key: " .. key)
	end
end
function M.close_key_hint_windows_if_open()
	if #M.main_window_key_hint_win_ids == 0 then return end
	for i, win_id in ipairs(M.main_window_key_hint_win_ids) do
		local success, err = pcall(function()
			vim.api.nvim_win_close(win_id, true)
		end)
		if err then
			-- vim.notify(
			-- 	tostring(i) .. " close_key_hint_windows_if_open failed with: "
			-- 	.. vim.inspect(err) .. " " .. vim.inspect(win_id)
			-- )
		end
	end
	M.win_id_of_selected_key_hint = nil
	M.main_window_key_hint_win_ids = {}
end
function M.close_secondary_window_if_open()
	if M.secondary_window == nil then return end
	local win_id = M.secondary_window.win_id, true
	local success, err = pcall(function()
		vim.api.nvim_win_close(win_id, true)
		M.secondary_window = nil
	end)
	if err then
		-- vim.notify("close_secondary_window_if_open failed with: " .. vim.inspect(err) .. " " .. vim.inspect(win_id))
	end
end
function M.close_main_window_if_open()
	if M.main_window == nil then return end
	local win_id = M.main_window.win_id, true
	local success, err = pcall(function()
		vim.api.nvim_win_close(win_id, true)
		M.main_window = nil
	end)
	if err then
		-- vim.notify("close_secondary_window_if_open failed with: " .. vim.inspect(err) .. " " .. vim.inspect(win_id))
	end
end

function index_of(value, table)
	for i, v in ipairs(table) do
		if v == value then return i end
	end
	return nil
end

function M.handle_input(input)
	if input == M.config.openTypeDocKeymap then
		M.close_secondary_window_if_open()
		M.close_main_window_if_open()
		M.close_key_hint_windows_if_open()
		M.restore_mappings()
		M.listening_for_input = false
		-- vim.notify("Stopped listening. M.listening_for_input: " .. tostring(M.listening_for_input))
		vim.keymap.set('n', M.config.openTypeDocKeymap, M.better_type_hover)
		return
	end

	local index_of_input = index_of(input, M.config.keys_that_open_nested_types)
	if index_of_input ~= nil then

		local no_key_hint_visible_with_that_letter = index_of_input > #M.main_window_key_hint_win_ids
		if no_key_hint_visible_with_that_letter then
			return
		end

		-- vim.notify("open_secondary_window(" .. index_of_input .. ") " .. tostring(index_of_input) .. " " .. input)

		M.open_secondary_window(index_of_input)

		for _, win_id in ipairs(M.main_window_key_hint_win_ids) do
			local buf = vim.api.nvim_win_get_buf(win_id)
			vim.api.nvim_buf_clear_namespace(buf, selected_key_hint_color_namespace, 0, -1)
		end

		-- vim.notify(vim.inspect(M.main_window_key_hint_win_ids))
		local win_id = M.main_window_key_hint_win_ids[index_of_input]
		-- vim.notify("coloring red win_id: " .. tostring(win_id))
		M.win_id_of_selected_key_hint = win_id
		local buf = vim.api.nvim_win_get_buf(win_id)
		vim.api.nvim_buf_add_highlight(buf, selected_key_hint_color_namespace, "selected_key_hint_color", 0, 0, -1)
	else
		M.restore_mappings()
		M.listening_for_input = false
		-- vim.notify("Stopped listening")
		return
	end

	-- Stop listening after a key is pressed

end

function M.listen_for_one_input_key()
	-- vim.notify("listen_for_one_input_key ... A .. " .. tostring(M.listening_for_input))
	if M.listening_for_input == true then
		-- vim.notify("listening_for_input is true")
		return -- Don't do anything if already listening
	end
	M.listening_for_input = true
	-- vim.notify("Listening for input...")

	-- vim.notify("listen_for_one_input_key ... B")

	-- Store current mappings to restore them later
	M.store_mappings()

	-- Map the keypresses for input when listening is active
	vim.keymap.set(
		'n', M.config.openTypeDocKeymap,
		function()M.handle_input(M.config.openTypeDocKeymap)end, { noremap=true, silent=true }
	)
	for _, key in ipairs(M.config.keys_that_open_nested_types) do
		vim.keymap.set('n', key, function()M.handle_input(key)end, { noremap=true, silent=true })
	end
end


---show floating window
---@param lines string[]
-- -@param callback fun(): nil -- called just before calling `listen_for_one_input_key()`
function M.showHoverDoc(
	lines, add_to_row, is_main_doc, filename, start_line, items
)
	local floating_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(floating_buf, 0, -1, false, lines)

	-- if apply_custom_syntax_highlighting then
	-- 	M.apply_syntax_highlighting(floating_buf)
	-- else
	vim.bo[floating_buf].filetype = "typescript"
	-- end

	local longest_line_length = 0;
	local longest_line = ""
	for _, line in ipairs(lines) do
		if #line > longest_line_length then
			longest_line_length = #line
			longest_line = line
		end
	end


	if is_main_doc then
		local opts = {
			relative = "cursor",
			width = vim.fn.strdisplaywidth(longest_line),
			height = #lines,
			col = 1,
			row = 1 + (add_to_row or 0),
			style = "minimal",
			border = "rounded",
			anchor = "NW",
		}

		M.close_main_window_if_open()
		M.close_secondary_window_if_open()

		local win_id = vim.api.nvim_open_win(floating_buf, false, opts)

		local uri = nil
		if filename ~= nil then
			uri = vim.uri_from_fname(filename)
		end
		M.main_window = {
			lines=lines,
			items=items,
			start_line=start_line,
			end_line=-1,
			uri=uri,
			filename=filename,
			win_id=win_id,
		}

		M.listen_for_one_input_key()

		vim.api.nvim_create_autocmd("CursorMoved", {
			once = true,
			callback = function()
				if M.listening_for_input == true then
					M.listening_for_input = false
					M.restore_mappings()
					vim.keymap.set('n', M.config.openTypeDocKeymap, M.better_type_hover)
					-- vim.notify("Stopped listening")
				end
				M.close_main_window_if_open()
				M.close_secondary_window_if_open()
				M.close_key_hint_windows_if_open()
			end,
			desc = "Close float win when cursor on moved"
		})
	else
		if M.main_window == nil then
			-- vim.notify("No main_window found to place secondary_window relative to")
			return
		end

		local opts = {
			relative = "win",
			win = M.main_window.win_id,
			width = vim.fn.strdisplaywidth(longest_line),
			height = #lines,
			col = -1,
			row = #(M.main_window.lines) + 1,
			style = "minimal",
			border = "rounded",
			anchor = "NW",
		}
		M.close_secondary_window_if_open()

		if M.secondary_window ~= nil and M.secondary_window.win_id ~= nil then
			-- vim.notify("Critical. secondary_item.win_id should be nil at this point!")
		end

		local win_id = vim.api.nvim_open_win(floating_buf, false, opts)

		M.secondary_window = {
			lines=lines,
			items=items,
			start_line=start_line,
			end_line=-1,
			uri="",
			filename="",
			win_id=win_id,
		}

		M.listen_for_one_input_key()
	end
end


function M.filterForInterfaceOrTypeDeclarations(items)
	-- Filter only interfaces and types
	local filtered_items = {}
	for _, item in ipairs(items) do
		if item.filename then
			vim.fn.bufload(item.filename)
			local bufnr = vim.fn.bufnr(item.filename)
			if bufnr ~= -1 then
				local _start = item['user_data']['targetRange']['start']['line']
				local _end = item['user_data']['targetRange']['end']['line']
				local lines = vim.api.nvim_buf_get_lines(bufnr, _start, _end + 3, false)
				local line = lines[1] or ""
				if string.match(line, "^%s*interface") or
					string.match(line, "^%s*export interface") or
					string.match(line, "^%s*export type") or
					string.match(line, "^%s*type")
				then
					table.insert(filtered_items, item)
				end
			end
		end
	end
	return filtered_items
end

function is_table_empty(table)
	return next(table) == nil
end

---@field filename string The filename of where the nested type is declared
function M.extract_lines_of_nested_type(filename, row, col)
	local bufnr = vim.fn.bufadd(filename)
	vim.fn.bufload(filename)
	local params = {
		textDocument = { uri = vim.uri_from_fname(filename) },  -- Convert file to uri
		position = { line = row-1, character = col },  -- Convert to 0-indexed for LSP
	}
	vim.lsp.buf_request(bufnr, 'textDocument/definition', params, function(err, result)
		if result == nil or is_table_empty(result) then
			-- vim.notify("Result is nil")
			return
		end

		local filename = vim.uri_to_fname(result[1].targetUri)
		local bufnr = vim.fn.bufadd(filename)
		vim.fn.bufload(filename)

		local _start = result[1]['targetRange']['start']['line']
		local _end = result[1]['targetRange']['end']['line']
		local _end2 = math.min(_end + 1, _start + M.config.fold_lines_after_line)
		local lines = vim.api.nvim_buf_get_lines(bufnr, _start, _end2, false)
		if #lines == 0 then return end
		lines = M.reindent_lines(lines)
		if _end2 ~= _end + 1 then
			table.insert(lines, "/* Folded lines below */")
		end
		-- for i, line in ipairs(lines) do
		-- 	vim.notify(i .. " line: '" .. line .. "'")
		-- end

		M.showHoverDoc(lines, 0, false)
	end)
end
function M.does_contain_any(str, patterns)
	for _, type in ipairs(patterns) do
		local _, _, match = string.find(str, ".-:%s*(" .. type .. ")")
		if match then
			-- vim.notify("found match: " .. match .. " type: " .. type, vim.log.levels.TRACE)
			return nil, true
		end
	end
	local _, end_col, m = string.find(str, ".-:%s*([%w_])")
	if m then
		-- vim.notify("DEBUG: " .. vim.inspect(end_col) .. ", str: " .. str .. ", match: " .. vim.inspect(m))
		return end_col, false
	end
	return nil, true
end
function M.highlight_keyword(buf, keyword, highlight_group)
	-- Get the total number of lines in the buffer
	local total_lines = vim.api.nvim_buf_line_count(buf)

	-- Iterate through each line in the buffer
	for line_num = 0, total_lines - 1 do
		-- Get the line content
		local line = vim.api.nvim_buf_get_lines(buf, line_num, line_num + 1, false)[1]

		-- Search for all occurrences of the keyword in the line using Lua string.find
		local start_pos = 1
		while true do
			local s, e = string.find(line, keyword, start_pos)  -- Find occurrences of the keyword
			if not s then break end  -- No more occurrences

			-- Apply the highlight to the matched occurrence in the buffer
			vim.api.nvim_buf_add_highlight(buf, -1, highlight_group, line_num, s - 1, e)

			-- Move the start position to search for the next occurrence in the line
			start_pos = e + 1
		end
	end
end
---@important call this *after* you set the lines in the buffer
function M.apply_syntax_highlighting(floating_buf)
	-- Default color
	local bufnr = vim.api.nvim_get_current_buf()
	local line_count = vim.api.nvim_buf_line_count(bufnr)

	for line = 0, line_count - 1 do
		vim.api.nvim_buf_add_highlightt(bufnr, -1, "BlueText", line, 0, -1)
	end

	-- Define highlight groups
	vim.cmd('highlight ExportColor guifg=#86e1fc guibg=NONE')  -- Keyword color
	vim.cmd('highlight IntefaceColor guifg=#e69bd9 guibg=NONE')  -- Comment color
	vim.cmd('highlight IntefaceNameColor guifg=#e69bd9 guibg=NONE')  -- Comment color
	vim.cmd('highlight PrimitiveTypeColor guifg=#589ed7 guibg=NONE')   -- String color
	vim.cmd('highlight FieldVariableName guifg=#4bc5b0 guibg=NONE')   -- String color
	vim.cmd('highlight NestedType guifg=#589ed7 guibg=NONE')     -- Type color
	vim.cmd('highlight MyDefault guifg=#d4d4d4 guibg=NONE')  -- Default text color (gray)

	M.highlight_keyword(floating_buf, 'export', 'ExportColor')
	M.highlight_keyword(floating_buf, 'interface', 'IntefaceColor')
	M.highlight_keyword(floating_buf, 'extends', 'IntefaceColor')
	M.highlight_keyword(floating_buf, 'number', 'PrimitiveTypeColor')
	M.highlight_keyword(floating_buf, 'string', 'PrimitiveTypeColor')
	M.highlight_keyword(floating_buf, 'boolean', 'PrimitiveTypeColor')

	-- local win_id = vim.api.nvim_open_win(floating_buf, false, opts)
end
---@class expandable_type
---@field line_number_in_file number line number in the file it's declared in
---@field line_number_in_declaration number line number counting from the declaration of the type
---@field start_col number

---@param lines string[]
---@return expandable_type[]
function M.find_expandable_types(lines, _start)
	local expandable_types = {}
	for index, line in ipairs(lines) do
		local start_col, doesLineNotContainAnyExpandableType = M.does_contain_any(line, M.config.types_to_not_expand)
		if not doesLineNotContainAnyExpandableType then
			table.insert(expandable_types, {
				line_number_in_file=_start+index,
				line_number_in_declaration=index,
				start_col=start_col,
			})
			-- vim.notify("line contains expandable type: " .. _start .. " " .. index .. " " .. vim.inspect(start_col) .. " line: " .. line, vim.log.levels.TRACE, { silent=true })
		else
			-- vim.notify("line does not contain expandable type: " .. _start .. " " .. index .. " " .. vim.inspect(start_col) .. " line: " .. line, vim.log.levels.TRACE, { silent=true })
		end
	end
	return expandable_types
end

function get_longest_string_in_list(list)
	local longest_string_length = 0;
	local longest_string = ""
	for _, line in ipairs(list) do
		if #line > longest_string_length then
			longest_string_length = #line
			longest_string = line
		end
	end
	return longest_string
end

---@param expandable_types expandable_type[]
function M.show_key_hints_in_primary_window(expandable_types)
	-- vim.notify("show_key_hints_in_primary_window ")
	-- vim.notify("show_key_hints_in_primary_window " .. M.main_window.win_id)
	for i, expandable_type in ipairs(expandable_types) do
		local floating_buf = vim.api.nvim_create_buf(false, true)
		local key_that_open_nested_type = M.config.keys_that_open_nested_types[i]
		local lines = {key_that_open_nested_type}
		-- local lines = {"asdf asdf asdf asdf ", "a dsf asdfj asdsadf ", "klasdflasdfl "}
		vim.api.nvim_buf_set_lines(floating_buf, 0, -1, false, lines)
		local opts = {
			relative = "cursor",
			-- win_id = M.main_window.win_id,
			width = vim.fn.strdisplaywidth(get_longest_string_in_list(lines)),
			height = 1,
			col = 2,
			row = 1 + expandable_type.line_number_in_declaration,
			style = "minimal",
			border = "none",
			anchor = "NW",
		}
		-- vim.notify("opening win" .. tostring(#lines))
		local win_id = vim.api.nvim_open_win(floating_buf, false, opts)
		table.insert(M.main_window_key_hint_win_ids, win_id)
	end
end
function M.extractDeclarations(items)
	local item = items[1]
	local bufnr = vim.fn.bufnr(item.filename)
	if bufnr == -1 then
		return
	end
	local _start = item['user_data']['targetRange']['start']['line']
	local _end = item['user_data']['targetRange']['end']['line']
	local _end2 = math.min(_end + 1, _start + M.config.fold_lines_after_line)
	local lines = vim.api.nvim_buf_get_lines(bufnr, _start, _end2, false)
	if _end2 ~= _end + 1 then
		table.insert(lines, "/* Folded lines below */")
	end
	for i, line in ipairs(lines) do
		-- vim.notify(i .. " line: '" .. line .. "'")
	end

	if #lines == 0 then return end

	lines = M.reindent_lines(lines)

	-- Check if we need to reindent the declaration in the popup
	local indent_content = string.match(lines[1], "^(%s+)")
	if indent_content ~= nil then
		-- We need to reindent all lines
		for i, line in ipairs(lines) do
			local reindented_line = string.sub(line, #indent_content + 1)
			lines[i] = reindented_line
		end
	end

	local expandable_types = M.find_expandable_types(lines, _start)

	local callback = function()M.show_key_hints_in_primary_window(expandable_types)end
	callback()

	M.showHoverDoc(lines, 0, true, item.filename, nil, items)
end

---@return string[]
function M.reindent_lines(lines)
	-- Check if we need to reindent the declaration in the popup
	local indent_content = string.match(lines[1], "^(%s+)")
	if indent_content ~= nil then
		-- We need to reindent all lines
		for i, line in ipairs(lines) do
			local reindented_line = string.sub(line, #indent_content + 1)
			lines[i] = reindented_line
		end
	end
	return lines
end

function M.open_secondary_window(index_of_nested_type)
	if M.main_window == nil then
		-- vim.notify("main_item is nil")
		return
	end
	local items = M.main_window.items
	if items == nil or #items == 0 then
		-- vim.notify("There are no items")
		return
	end

	local bufnr = vim.fn.bufnr(M.main_window.filename)
	local _start = items[1]['user_data']['targetRange']['start']['line']
	local _end = items[1]['user_data']['targetRange']['end']['line']
	local lines = vim.api.nvim_buf_get_lines(bufnr, _start, _end + 1, false)

	local expandable_types = M.find_expandable_types(lines, _start)

	-- vim.notify("expandable_types len: " .. vim.inspect(#expandable_types), vim.log.levels.TRACE)

	for index, expandable_type in ipairs(expandable_types) do
		if index == index_of_nested_type then
			local row = expandable_type.line_number_in_file
			local col = expandable_type.start_col
			M.extract_lines_of_nested_type(M.main_window.filename, row, col)
			return
		end
	end

end

function M.format_function_signature(signature)
	return signature:gsub("%b{}", function(param_block)
		-- Check if the param_block inside curly braces is not empty
		local content = param_block:sub(2, -2) -- Remove the surrounding braces
		if content ~= "" then
			-- Format the non-empty param_block
			return "{\n\t" .. content:gsub(", ", ",\n\t") .. "\n}"
		else
			-- Return the original if the block is empty
			return param_block
		end
	end)
end

function M.prettifyDeclarationString(lines)
	lines = M.format_function_signature(lines)
	lines = vim.split(lines, "\n", { trimempty = true })
	return lines
end

function M.open_primary_window()
	vim.lsp.buf.definition({
		on_list = function(options)
			local items = options.items or {}

			if #items > 0 then
				local interfaceOrTypeItemsOnly = M.filterForInterfaceOrTypeDeclarations(items)

				if #interfaceOrTypeItemsOnly > 0 then
					-- vim.notify("interface or type encountered")
					M.extractDeclarations(interfaceOrTypeItemsOnly)
					return -- TODO remove this
				end

				if M.config.fallback_to_old_on_anything_but_interface_and_type == true then
					vim.lsp.buf.hover()
					return
				end

				-- vim.notify("No interface or type definitions found. Resorting to vim.lsp.buf.hover()", vim.log.levels.WARN)

				-- vim.lsp.buf_request(0, "textDocument/hover", POSITION_PARAMS, function(err, result, ctx, config)
				-- 	if result ~= nil then
				-- 		-- vim.notify("hover: " .. vim.inspect(result))
				-- 		local value = result["contents"]["value"]
				-- 		local start_index, end_index, match = string.find(value, "\n```typescript\n(.-)\n```\n")
				-- 		if match ~= nil then
				-- 			vim.notify("textDocument/hover: " .. vim.inspect(match))
				-- 			showHoverDoc({match})
				-- 			return
				-- 		end
				-- 		-- vim.notify("no match: " .. vim.inspect(match))
				-- 	end
				-- 	-- vim.notify("hover (err): " .. vim.inspect(err))
				-- end)

				-- vim.lsp.buf.hover() -- Resort to using the hover provided by the lsp
				-- return
			end
			-- vim.notify("Not an interface nor type: ")


			local POSITION_PARAMS = vim.lsp.util.make_position_params()
			vim.lsp.buf_request(0, "textDocument/hover", POSITION_PARAMS,
				function(err, result)
					if result ~= nil then
						local line_with_linebreaks = result["contents"]["value"]
						-- vim.notify(vim.inspect(line_with_linebreaks), vim.log.levels.TRACE)
						local start_index, end_index, property_match = string.find(line_with_linebreaks, "\n```typescript\n%(property%) (.-: [^\n]+)")
						local start_index, end_index, alias_match = string.find(line_with_linebreaks, "\n```typescript\n%(alias%) (.-)\nimport ")
						local start_index, end_index, parameter_match = string.find(line_with_linebreaks, "\n```typescript\n%(parameter%) (.-: [^\n]+)")
						local start_index, end_index, local_function_match = string.find(line_with_linebreaks, "\n```typescript\n%(local function%) (.-: [^\n]+)")
						local start_index, end_index, match = string.find(line_with_linebreaks, "\n```typescript\n(.-)\n```\n")
						-- vim.notify("match: " .. vim.inspect(match) .. " type: " .. type(match) .. " " .. vim.inspect(start_index) .. " " .. vim.inspect(end_index))
						if property_match ~= nil then
							-- vim.notify("It s a property: " .. match)
							-- vim.notify("textDocument/hover property_match " .. vim.inspect(property_match), vim.log.levels.TRACE, { silent=true })
							M.showHoverDoc({property_match}, 0, true, nil)
							return
						elseif property_match ~= nil then
							-- vim.notify("textDocument/hover local_function_match " .. vim.inspect(local_function_match), vim.log.levels.TRACE, { silent=true })
							M.showHoverDoc({local_function_match}, 0, true, nil)
							return
						elseif alias_match then
							-- vim.notify("textDocument/hover alias_match " .. vim.inspect(alias_match), vim.log.levels.TRACE, { silent=true })
							-- ignore this
							local lines = M.prettifyDeclarationString(alias_match)
							-- vim.notify("prettifiedLines: " .. vim.inspect(lines), vim.log.levels.TRACE, { silent=true })
							M.showHoverDoc(lines, 0, true, nil)
							return
						elseif parameter_match then
							-- vim.notify("textDocument/hover parameter_match " .. vim.inspect(parameter_match), vim.log.levels.TRACE, { silent=true })
							M.showHoverDoc({parameter_match}, 0, true, nil)
							return
						elseif match then
							-- vim.notify("textDocument/hover match " .. vim.inspect(match), vim.log.levels.TRACE, { silent=true })
							M.showHoverDoc({match}, 0, true, nil)
							return
						end
					end

					vim.lsp.buf_request(0, "textDocument/signatureHelp", POSITION_PARAMS, function(err, result, ctx, config)
						-- vim.notify("result,err: " .. vim.inspect(result) .. " err:" .. vim.inspect(err))
						if result ~= nil then
							local lines = result["signatures"][1]["label"]
							local shouldShowAsDeclaration = not string.find(lines, "^callbackfn")
							if shouldShowAsDeclaration then
								lines = M.prettifyDeclarationString(lines)
								-- vim.notify("SignatureHelp", vim.log.levels.TRACE)
								M.showHoverDoc(lines, 0, true, nil)
								return
							end
						end

						-- vim.notify("signatureHelp err: " ..vim.inspect(err)) -- This will show the actual signature help result
						-- vim.notify("No definition found. Resorting to vim.lsp.buf.hover()", vim.log.levels.INFO)
						vim.lsp.buf.hover() -- Resort to using the hover provided by the lsp
					end)


				end
			)

		end,
	})
end


return M
