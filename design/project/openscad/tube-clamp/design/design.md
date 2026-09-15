# Tube clamp — OpenSCAD design



## Goal of the base clip

This component is the reusable **basic tube clip**, not yet a complete mounting
solution.

The clip therefore gets only a compact flat back. That flat surface is part of
the clip shape itself and does **not** extend sideways into a mounting plate.

A later consumer or library variant can decide how the clip is actually
mounted, for example with one screw below the tube or with an extended plate
and two screw holes.

For the base clip the rule is simple:

> the flat base is exactly as wide as the lower edge of the sloped transition.

There is therefore no independent base-width or mounting-plate-width parameter.

## Main parameters

Tube geometry:

```scad
tube_diameter = 20;
clearance = 0.0;
wall_thickness = 3;
clamp_width = 16;
opening_angle = 60;
```

Compact back geometry:

```scad
base_thickness = 4;
transition_width = 30;
transition_depth = 8;
```

- `base_thickness` — thickness measured from the flat rear surface toward the
  clip;
- `transition_width` — total width of both the compact base and the lower edge
  of the sloped transition;
- `transition_depth` — distance from the front of the compact base toward the
  circular body before the transition meets the circle.

The base width is deliberately derived from `transition_width`.

## Construction order

The model is built as an ordinary solid part:

```text
complete outside shape
        ↓
remove tube bore
        ↓
remove snap opening
        ↓
final clip
```

The tube bore is therefore **one Boolean cut through the completed outside
shape**. It is not cut from the ring and then cut a second time from the
transition.

The design images follow exactly this order.

## 1. Solid circular outside

We start with the solid outside cylinder of the clip. There is intentionally no
tube hole yet.

```scad
module _outer_ring_solid(clamp) {
    translate([_tube_clamp_center_x(clamp), 0, 0])
        cylinder(
            h = clamp.clamp_width,
            r = tube_clamp_outer_radius(clamp)
        );
}
```

![Outer Ring](img/01-outer-ring.png)

## 2. Compact flat base

The flat rear surface is added next. Existing geometry is gray; new geometry is
transparent red.

```scad
module _flat_base(clamp) {
    translate([
        0,
        -clamp.transition_width / 2,
        0
    ])
        cube([
            clamp.base_thickness,
            clamp.transition_width,
            clamp.clamp_width
        ]);
}
```

The important part is that the base uses `transition_width` directly. It cannot
stick out farther than the transition underneath it.

![Base](img/02-base.png)

## 3. Sloped transition

The transition joins the compact base to the round outside.

```scad
polygon(points = [
    [clamp.base_thickness, -base_half_width],
    [clamp.base_thickness,  base_half_width],
    [attach_x,               attach_y],
    [attach_x,              -attach_y]
]);
```

At the end of this step the complete outside is one solid union:

```scad
module _outer_shape(clamp) {
    union() {
        _outer_ring_solid(clamp);
        _flat_base(clamp);
        _base_transition(clamp);
    }
}
```

No holes have been made yet.

![Transition](img/03-transition.png)

## 4. Tube bore

Now the cylindrical space for the tube is removed from that completed outside.

The outside is shown semi-transparent gray and the cutter is red.

```scad
difference() {
    _outer_shape(clamp);
    _inner_bore_cutter(clamp);
}
```

This is the only tube-bore subtraction in the construction.

![Bore](img/04-bore.png)

## 5. Snap opening

The hollow body is still closed. The triangular cutter creates the snap
opening.

```scad
cutter_length = outer_r + 10;
cutter_half_width =
    cutter_length * tan(clamp.opening_angle / 2);
```

![Opening](img/05-opening.png)

## 6. Final base clip

The public build is now a direct expression of the design sequence:

```scad
module tube_clamp_build(clamp) {
    difference() {
        _outer_shape(clamp);

        _inner_bore_cutter(clamp);
        _opening_cutter(clamp);
    }
}
```

The result has a useful compact flat back but still makes no assumptions about
how a project will fasten it.

![Final](img/06-final.png)

## 7. Profile view

The profile view looks directly along the clamp width and is intended for
judging:

- `base_thickness`;
- `transition_width`;
- `transition_depth`;
- the overlap between the circular body and the compact base.

![Profile](img/07-profile.png)

## Public object API

```scad
clamp = tube_clamp_create(
    tube_diameter = 20,
    clearance = 0.0,
    wall_thickness = 3,
    clamp_width = 16,
    opening_angle = 60,
    base_thickness = 4,
    transition_width = 30,
    transition_depth = 8
);

tube_clamp_build(clamp);
```

OpenSCAD `object()` remains the preferred struct-like API for reusable
components in this repository.

CLI rendering therefore still requires:

```bash
openscad --enable=object-function ...
```

## Possible later mounting variants

Not implemented here.

The compact base gives later variants a clean starting point, for example:

```text
basic tube clamp
├── single-screw variant
└── extended two-screw mounting-plate variant
```

Those variants should add mounting geometry to the reusable base clip instead
of turning the basic clip itself into a project-specific mount.
