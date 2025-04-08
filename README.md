This plugin is still work in progress. Currently, the mapping to trigger this "better-type-hover" is hardcoded to `<C-P>`. I would love some feedback.

# The problem

The ts_ls (typescript lsp) `vim.lsp.buf.hover()` is in many cases completely useless:

![image](https://github.com/user-attachments/assets/a30b638a-2d06-4861-9330-0375a2c4a828)

This plugin improves `vim.lsp.buf.hover()` by actually showing the exact declaration of the `interface` or `type` (crazy how that's not the default 🤔). 

# Installation

Lazy.nvim
```lua
{
  "Sebastian-Nielsen/better-type-hover",
  config = function()
    
  end,
}
```

# Todo:

- [x] Configure how to treat large interface declarations: Fold some lines or maybe show it all but make the popup scrollable
- [ ] Handle that a nested type is e.g. `style?: StyleHTMLAttributes<HTMLDivElement> & CSSProperties;`. Currently, it only expands the left-most (`StyleHTMLAttributes<HTMLDivElement>` in this case)
- [x] reindent declaration in case it is indented
