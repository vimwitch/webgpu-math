// 128 bit numbers = 4 * 32 bit values
// v[0] = least significant
// v[tuple_size - 1] = most significant
const tuple_size = 4u;
const tuple_size_double = 2u * tuple_size;
const tuple_size_quad = 4u * tuple_size;
const tuple_bits = tuple_size * 32u;

const iterations = {iterations}u;

const upper_mask: u32 = 0xffff0000u;
const lower_mask: u32 = 0x0000ffffu;

@group(0)
@binding(0)
var<storage, read> input0: array<array<u32, tuple_size>, iterations>;

@group(0)
@binding(1)
var<storage, read_write> input1: array<array<u32, tuple_size>, iterations>;

@group(0)
@binding(3)
var<storage, read_write> outputs: array<array<u32, tuple_size>, iterations>;

const barrett_p: array<u32, 4> = array(
        1u,
        0u,
        0u,
        3414163456u
    );
const barrett_r = array(
        4052254154u,
        2754266496u,
        3851751997u,
        1108038245u,
        1u,
        0u, 0u, 0u
        );

// var<storage, read_write> sum_terms: array<array<array<u32, tuple_size_double>, tuple_size_double>, iterations>;


// TODO: test this
fn addmod(
    in0: array<u32, tuple_size>,
    in1: array<u32, tuple_size>
) -> array<u32, tuple_size> \{
    var sum = add(in0, in1);
    if gte(sum, barrett_p) \{
        return sub(sum, barrett_p);
    }
    return sum;
}

fn submod(
    in0: array<u32, tuple_size>,
    in1: array<u32, tuple_size>
) -> array<u32, tuple_size> \{
    var v = in0;
    if gt(in1, in0) \{
        v = add(v, barrett_p);
    }
    return sub(v, in1);
}

// limb based addition, not modular, overflows wrap
// break each limb into 16 bit sections and add
// take the upper bits as the carry
fn add(
    in0: array<u32, tuple_size>,
    in1: array<u32, tuple_size>
) -> array<u32, tuple_size> \{
    var out: array<u32, tuple_size>;
    var carry: u32;
    var i: u32;
    {{ for _ in tuple_arr }}
    \{
        i = { @index }u;
        out[{ @index }u] = in0[{ @index }u] + in1[{ @index }u] + carry;
        carry = u32((out[{ @index }u] < in0[{ @index }u]) || (out[{ @index }u] < in1[{ @index }u]));
    }
    {{ endfor }}
    return out;
}

fn add_double(
    in0: array<u32, tuple_size_double>,
    in1: array<u32, tuple_size_double>,
) -> array<u32, tuple_size_double> \{
    var out: array<u32, tuple_size_double>;
    var carry: u32;

    {{ for _ in tuple_arr_double }}
    \{
        out[{ @index }u] = in0[{ @index }u] + in1[{ @index }u] + carry;
        carry = u32((out[{ @index }u] < in0[{ @index }u]) || (out[{ @index }u] < in1[{ @index }u]));
    }
    {{ endfor }}
    return out;
}

fn add_quad(
    in0: ptr<function, array<u32, tuple_size_quad>>,
    in1: ptr<function, array<u32, tuple_size_quad>>,
    out: ptr<function, array<u32, tuple_size_quad>>
) \{
    var carry: u32;

    for (var i: u32 = 0u; i < tuple_size_quad; i++) \{
        (*out)[i] = (*in0)[i] + (*in1)[i] + carry;
        carry = u32(((*out)[i] < (*in0)[i]) || ((*out)[i] < (*in1)[i]));
    }
}

// negate and add
fn sub(
    in0: array<u32, tuple_size>,
    in1: array<u32, tuple_size>
) -> array<u32, tuple_size> \{
    var out: array<u32, tuple_size>;
    // negative carry
    var carry: u32;
    {{ for _ in tuple_arr }}
    \{
        out[{@index}u] = in0[{@index}u] - in1[{@index}u] - carry;
        carry = u32(out[{@index}u] > in0[{@index}u]);
    }
    {{ endfor }}
    return out;
}

fn sub_double(
    in0: array<u32, tuple_size_double>,
    in1: array<u32, tuple_size_double>
) -> array<u32, tuple_size_double> \{
    // negative carry
    var out: array<u32, tuple_size_double>;
    var carry: u32;
    {{ for _ in tuple_arr_double }}
    \{
        out[{@index}u] = in0[{@index}u] - in1[{@index}u] - carry;
        carry = u32(out[{@index}u] > in0[{@index}u]);
    }
    {{ endfor }}
    return out;
}

fn gt(
    in0: array<u32, tuple_size>,
    in1: array<u32, tuple_size>
) -> bool \{
    {{ for i in tuple_arr_reverse }}
    \{
        if in0[{i}u] > in1[{i}u] \{
            return true;
        } else if in0[{i}u] < in1[{i}u] \{
            return false;
        }
    }
    {{ endfor }}
    return false;
}

fn gte(
    in0: array<u32, tuple_size>,
    in1: array<u32, tuple_size>
) -> bool \{
    {{ for i in tuple_arr_reverse }}
    \{
        if in0[{i}u] > in1[{i}u] \{
            return true;
        } else if in0[{i}u] < in1[{i}u] \{
            return false;
        }
    }
    {{ endfor }}
    return true;
}

fn barrett(
    v: array<u32, tuple_size_double>
) -> array<u32, tuple_size> \{
    var out: array<u32, tuple_size>;
    var m = mul_r(v);
    var z = mul(barrett_p, m);
    var f = sub_double(v, z);
    for (var i: u32 = 0u; i < tuple_size; i++) \{
        out[i] = f[i];
    }
    return out;
}

fn mul_r(
    in0: array<u32, tuple_size_double>
) -> array<u32, tuple_size> \{
    // each result needs to be shifted by i*16 bits
    // var r = array(
    //     4052254154u,
    //     2754266496u,
    //     3851751997u,
    //     1108038245u,
    //     1u,
    //     0u, 0u, 0u
    // );
    var results: array<array<u32, tuple_size_quad>, tuple_size_quad>;
    {{ for _ in tuple_arr_double }}
    \{
        let index = { @index }u*2u;
        results[index] = mul_16_double(
            in0,
            barrett_r[{@index}u] & lower_mask,
            16u * index
        );
        results[index + 1u] = mul_16_double(
            in0,
            barrett_r[{@index}u] >> 16u,
            16u * (index + 1u)
        );
    }
    {{ endfor }}
    // do final sum
    var count: u32 = tuple_size_quad;
    while (count > 1u) \{
        for (var i: u32 = 0u; i < count; i += 2u) \{
            var t1 = results[i];
            var t2 = results[i + 1u];
            var j: array<u32, tuple_size_quad>;
            add_quad(&t1, &t2, &j);
            results[i/2u] = j;
        }
        count >>= 1u;
    }
    var out: array<u32, tuple_size>;
    for (var i: u32 = 0u; i < tuple_size; i++) \{
        out[i] = results[0u][i + tuple_size_double];
    }
    return out;
}

fn mul_16_double(
    in0: array<u32, tuple_size_double>,
    in1: u32,
    left_shift: u32
) -> array<u32, tuple_size_quad> \{
    var out: array<u32, tuple_size_quad>;
    // u32 * u32 = array<u32, 2>
    var carry: u32;
    let shift_registers = left_shift / 32u;
    let shift_bits = left_shift % 32u;
    {{ for _ in tuple_arr_double }}
    \{
        // multiply the lower bits by in1
        var lower = in0[{@index}u] & lower_mask;
        // add the carry to the product
        var r0 = lower * in1 + carry;
        // take the upper bits of the result as the carry
        carry = r0 >> 16u;

        // multiply the upper bits by in1
        var upper = in0[{@index}u] >> 16u;
        // add the carry to the product
        var r1 = upper * in1 + carry;

        out[{@index}u + shift_registers] = (r0 & lower_mask) + (r1 << 16u);
        carry = r1 >> 16u;
    }
    {{ endfor }}
    out[tuple_size_double + shift_registers] = carry;
    carry = 0u;
    for (var i: u32 = shift_registers; i < tuple_size_quad; i++) \{
        if shift_bits == 16u \{
            var old_carry = carry;
            carry = out[i] >> shift_bits;
            out[i] <<= shift_bits;
            out[i] += old_carry;
        }
    }
    return out;
}

fn mul(
    in0: array<u32, tuple_size>,
    in1: array<u32, tuple_size>,
) -> array<u32, tuple_size_double> \{
    // each result needs to be shifted by i*16 bits
    var results: array<array<u32, tuple_size_double>, tuple_size_double>;
    var index: u32;
    {{ for _ in tuple_arr }}
        index = { @index }u * 2u;
        results[index] = mul_16(
            in0,
            in1[{ @index }u] & lower_mask,
            16u * index
        );
        results[index + 1u] = mul_16(
            in0,
            in1[{ @index }u] >> 16u,
            16u * (index + 1u)
        );
    {{ endfor }}
    // do final sum
    var count: u32 = tuple_size_double;
    while (count > 1u) \{
        for (var i: u32 = 0u; i < count; i += 2u) \{
            var t1 = results[i];
            var t2 = results[i + 1u];
            var j = add_double(t1, t2);
            results[i/2u] = j;
        }
        count >>= 1u;
    }
    return results[0u];
}

// multiply a tuple number by a single 16 bit number
// end up with tuple_size + 1 limbs
fn mul_16(
    in0: array<u32, tuple_size>,
    in1: u32,
    left_shift: u32
) -> array<u32, tuple_size_double> \{
    var out: array<u32, tuple_size_double>;
    // u32 * u32 = array<u32, 2>
    var carry: u32;
    let shift_registers = left_shift / 32u;
    let shift_bits = left_shift % 32u;
    // var i: u32;
    {{ for _ in tuple_arr }}
    \{
        // i = { @index }u;
        // multiply the lower bits by in1
        var lower = in0[{ @index }u] & lower_mask;
        // add the carry to the product
        var r0 = lower * in1 + carry;
        // take the upper bits of the result as the carry
        carry = r0 >> 16u;

        // multiply the upper bits by in1
        var upper = in0[{ @index }u] >> 16u;
        // add the carry to the product
        var r1 = upper * in1 + carry;

        out[{ @index }u + shift_registers] = (r0 & lower_mask) + (r1 << 16u);
        carry = r1 >> 16u;
    }
    {{ endfor }}
    out[tuple_size + shift_registers] = carry;
    carry = 0u;
    {{ for _ in tuple_arr_double }}
    \{
        if shift_bits == 16u \{
            var old_carry = carry;
            carry = out[{@index}u] >> shift_bits;
            out[{@index}u] <<= shift_bits;
            out[{@index}u] += old_carry;
        }
    }
    {{ endfor }}
    return out;
}

fn mulmod(
    in0: array<u32, tuple_size>,
    in1: array<u32, tuple_size>
) -> array<u32, tuple_size> \{
    var r = mul(in0, in1);
    return barrett(r);
}

@compute
@workgroup_size(64)
fn test_ntt(
    @builtin(global_invocation_id) global_id: vec3<u32>,
    @builtin(local_invocation_id) local_id: vec3<u32>
) \{
    let _gap: u32 = 1u;
    var gap: u32 = 1u;
    while (gap < iterations) \{
        let chunks = iterations / (gap << 1u);
        let inc = 64u * (gap << 1u);
        // outer loop is indexed by the global invocation

        for (var i: u32 = global_id.x; i < iterations; i += inc) \{
            // inner loop is indexed by the local invocation
            for (var j: u32 = local_id.x; j < gap; j += 64u) \{
                // high = input1[i + j]
                // low = input1[i + gap + j]
                var hi = input1[i + j];
                var lo = input1[i + gap + j];
                var new_hi = mulmod(hi, input0[chunks * j]);
                // input[i + j] = new_high;
                var neg = submod(lo, new_hi);
                // set the new low value
                input1[i + gap + j] = addmod(lo, new_hi);
                // set the new high value
                input1[i + j] = neg;
            }

        }
        gap <<= 1u;
        storageBarrier();
    }
    // just to fix compile errors
    outputs[0][0] = 0u;
}


// Inputs to this function must be in the range of the field
@compute
@workgroup_size(64)
fn test_mul(
    @builtin(global_invocation_id) global_id: vec3<u32>
) \{
    outputs[global_id.x] = mulmod(input0[global_id.x], input1[global_id.x]);
}

// step 1: build the list of 16 bit multiplications to be performed
// step 2: build the list of tuple_size_double entries to be combined via addition
// step 3: combine the

@compute
@workgroup_size(64)
fn test_add(
    @builtin(global_invocation_id) global_id: vec3<u32>
) \{
    outputs[global_id.x] = add(input0[global_id.x], input1[global_id.x]);
}
