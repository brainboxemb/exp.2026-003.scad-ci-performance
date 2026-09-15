$fn = 96;

module benchmark_body() {
    difference() {
        minkowski() {
            cube([52, 38, 10], center = true);
            sphere(r = 3);
        }

        for (x = [-18, 0, 18])
            for (y = [-11, 11])
                translate([x, y, 0])
                    cylinder(h = 24, d = 6, center = true);

        translate([0, 0, 4])
            cube([28, 16, 10], center = true);
    }
}

benchmark_body();
