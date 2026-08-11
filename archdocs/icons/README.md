# icons/

Drop custom icon files here for anything `diagrams` doesn't ship a built-in
node for. As of this writing that's **External Secrets Operator (ESO)** —
it has no official icon in the `diagrams` package, so the closest correct
option is to source the real logo yourself (project README, brand assets
page, etc.) rather than have this boilerplate silently point at some
unverified image URL.

1. Save the icon as `icons/eso.png` (PNG or SVG, square works best).
2. Use it in a diagram script:

   ```python
   from archdocs import custom_icon

   eso = custom_icon("ESO", "eso.png")
   ```

The same `custom_icon()` helper works for any other tool that isn't in
`archdocs.icons.ICONS` — just save the file here and call
`custom_icon("Name", "filename.png")`.

If the file isn't present, `custom_icon()` raises a clear
`FileNotFoundError` immediately instead of letting Graphviz fail later
with a confusing rendering error.
