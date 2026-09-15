# lib.scad.clamps verification

This branch contains generated functional verification output for the library.

The verification tests use the public library APIs from separate consumer files
and build three clamps with different dimensions.

## OpenSCAD

![OpenSCAD API verification](openscad/tube-clamp-api.png)

- [STL export](openscad/tube-clamp-api.stl)

## PythonSCAD

![PythonSCAD API verification](pythonscad/tube-clamp-api.png)

- [STL export](pythonscad/tube-clamp-api.stl)



## What is verified

- the OpenSCAD and PythonSCAD libraries can be consumed from separate source files;
- three independent parametrized clamp instances can be created;
- the public build API produces geometry;
- derived radius calculations return the expected values;
- PNG rendering succeeds;
- STL export succeeds.
