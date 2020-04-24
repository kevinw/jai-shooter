AABB :: struct {
    pos: Vector2;
    extents: Vector2;
}

// Warning: these are not good or sound or sane 2D physics. Use at your own risk.

overlaps :: (a: *AABB, b: *AABB) -> bool {
    t := b.pos - a.pos;
    return abs(t.x) <= (a.extents.x + b.extents.x) &&
           abs(t.y) <= (a.extents.y + b.extents.y);
}

try_move :: (a: *AABB, delta: Vector2, static: []AABB) -> bool {

    overlaps_delta :: inline (a: *AABB, b: *AABB, delta: *Vector2) -> bool {
        t := b.pos - a.pos;
        << delta = make_vector2(abs(t.x), abs(t.y)) - a.extents - b.extents;
        return delta.x < 0 && delta.y < 0;
    }

    new_pos := a.pos + delta;
    for * static {
        collision: Vector2 = ---;
        if overlaps_delta(a, it, *collision) {
            if collision.x > 0 collision.x = 0;
            if collision.y > 0 collision.y = 0;

            if collision.x > collision.y
                new_pos.x -= sign(a.pos.x - it.pos.x) * collision.x;
            else 
                new_pos.y -= sign(a.pos.y - it.pos.y) * collision.y;
        }
    }

    a.pos = new_pos;
    return true;
}
