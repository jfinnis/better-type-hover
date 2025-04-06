This plugin is still work in progress. Currently, the mapping to trigger this "better-type-hover" is hardcoded to `<C-P>`. I would love some feedback.

# Installation

Currently, there is no config options to pass to setup. 

Lazy.nvim
```lua
{
  "Sebastian-Nielsen/better-type-hover",
  config = function()
    require("better-type-hover").setup()
  end,
}
```
