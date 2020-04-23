
make_rotation_matrix :: (angle: float /*degrees*/) -> Matrix4 {
    q: Quaternion;
    TO_RADIANS :: 3.141592 / 180.0;
    set_from_axis_and_angle(*q, 0, 1, 0, angle * TO_RADIANS);
    return make_rotation_matrix4(q);
}

make_scale_matrix :: (x: float, y: float, z: float) -> Matrix4 {
    m := matrix4_identity();
    m._11 = x;
    m._22 = y;
    m._33 = z;
    return m;
}

length_squared_vec2 :: inline (a: Vector2) -> float {
    return a.x*a.x + a.y*a.y;
}

normalize_vec2 :: inline (a: *Vector2) {
    v: Vector3;
    v.x = a.x;
    v.y = a.y;
    normalize(*v, fallback=make_vector3(0, 0, 0));
    <<a = v.xy;
}
