class Body {
	public var x:Float; public var y:Float; public var z:Float;
	public var vx:Float; public var vy:Float; public var vz:Float; public var mass:Float;
	public function new(x, y, z, vx, vy, vz, mass) {
		this.x = x; this.y = y; this.z = z; this.vx = vx; this.vy = vy; this.vz = vz; this.mass = mass;
	}
}
class NBody {
	static function main() {
		var pi = Math.PI, solarMass = 4 * pi * pi, dpy = 365.24;
		var bodies = [
			new Body(0, 0, 0, 0, 0, 0, solarMass),
			new Body(4.84143144246472090e+00, -1.16032004402742839e+00, -1.03622044471123109e-01, 1.66007664274403694e-03 * dpy, 7.69901118419740425e-03 * dpy, -6.90460016972063023e-05 * dpy, 9.54791938424326609e-04 * solarMass),
			new Body(8.34336671824457987e+00, 4.12479856412430479e+00, -4.03523417114321381e-01, -2.76742510726862411e-03 * dpy, 4.99852801234917238e-03 * dpy, 2.30417297573763929e-05 * dpy, 2.85885980666130812e-04 * solarMass),
			new Body(1.28943695621391310e+01, -1.51111514016986312e+01, -2.23307578892655734e-01, 2.96460137564761618e-03 * dpy, 2.37847173959480950e-03 * dpy, -2.96589568540237556e-05 * dpy, 4.36624404335156298e-05 * solarMass),
			new Body(1.53796971148509165e+01, -2.59193146099879641e+01, 1.79258772950371181e-01, 2.68067772490389322e-03 * dpy, 1.62824170038242295e-03 * dpy, -9.51592254519715870e-05 * dpy, 5.15138902046611451e-05 * solarMass)
		];
		var dt = 0.01;
		for (step in 0...100000) {
			for (i in 0...bodies.length) {
				var b = bodies[i];
				for (j in i + 1...bodies.length) {
					var c = bodies[j];
					var dx = b.x - c.x, dy = b.y - c.y, dz = b.z - c.z;
					var d2 = dx * dx + dy * dy + dz * dz;
					var mag = dt / (d2 * Math.sqrt(d2));
					b.vx -= dx * c.mass * mag; b.vy -= dy * c.mass * mag; b.vz -= dz * c.mass * mag;
					c.vx += dx * b.mass * mag; c.vy += dy * b.mass * mag; c.vz += dz * b.mass * mag;
				}
			}
			for (b in bodies) { b.x += dt * b.vx; b.y += dt * b.vy; b.z += dt * b.vz; }
		}
		Sys.println(Math.round(bodies[0].x * 1e9));
	}
}
