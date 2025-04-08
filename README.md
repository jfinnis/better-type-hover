
# The problem

The ts_ls (typescript lsp) `vim.lsp.buf.hover()` is in many cases completely useless:

![image](https://github.com/user-attachments/assets/a30b638a-2d06-4861-9330-0375a2c4a828)

This plugin improves `vim.lsp.buf.hover()` by actually showing the exact declaration of the `interface` or `type` (crazy how that's not the default 🤔). 

Additionally, you can press the sign on the line to open yet another window with the declaration of the "nested type":


![somethign](https://gyazo.com/7ea66b405b1999248e7e145dc90cdd5a.gif)

#### Disclaimer

This plugin is really only meant to be used on `interface` or `type` in typescript. It can also be used on pretty much anything else where `vim.lsp.buf.hover()` is applicable. But be aware that if used on anything else that it might not always work, there is simply too many other such cases for me to be able to cover all of them. I intend to slowly add such cases as I discover them. 

# Installation

Lazy.nvim
```lua
{
  "Sebastian-Nielsen/better-type-hover",
  config = function()
    require("better-type-hover").setup() 
  end,
}
```

# Config

These are all the default options for reference:

```
require("better-type-hover").setup({
      -- If the declaration in the window is longer than 20 lines remove all lines after the 20th line. 
	    fold_lines_after_line = 20,
      -- The primary key to hit to open the main window
	    openTypeDocKeymap = "<C-P>",
      -- These letters/digits are used in order
	    keys_that_open_nested_types = { 'a', 's', 'h', 'j', 'k', 'l', 'b', 'i', 'e', 'u' },
      -- This is to avoid a type hint (i.e. a letter) showing up in the main window
	    types_to_not_expand = {"string", "number", "boolean", "Date"}
})
```

# Todo:

- [ ] Handle that a nested type is e.g. `style?: StyleHTMLAttributes<HTMLDivElement> & CSSProperties;`. Currently, it only expands the left-most (`StyleHTMLAttributes<HTMLDivElement>` in this case). 
