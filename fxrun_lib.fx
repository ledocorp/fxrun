// fxrun_lib — parse Fxrun.toml subset, list, depends, run (FX-APP-RUN-2 excellence).
// Design: docs/specs/FXRUN_LITE.md
// Storage: native Map<string,string> (emit-C + IR).
module fxrun_lib;

using core;
import std/io;
import std/string;
import std/strutil;

extern "c" {
    effects { io } fn fxrun_host_run_cmd(cmd: string) -> i32;
    effects { io } fn fxrun_host_ensure_dir(path: string) -> i32;
    effects { io, mut } fn fxrun_host_chdir_to_manifest() -> i32;
    effects { alloc } fn fxrun_host_slice(s: string, lo: i32, hi: i32) -> string;
    effects { alloc } fn fxrun_host_i32_dec(n: i32) -> string;
}

fn eq(a: string, b: string) -> bool {
    return string.compare(a, b);
}

fn slice(s: string, lo: i32, hi: i32) -> string effects { alloc } {
    return fxrun_host_slice(s, lo, hi);
}

fn map_get_or_empty(m: Map<string, string>, key: string) -> Result<string, core_Err> {
    if (map_contains(m, key) != true) {
        return Ok("");
    }
    let v = map_get(m, key)?;
    return Ok(v);
}

fn i32_dec(n: i32) -> string effects { alloc } {
    return fxrun_host_i32_dec(n);
}

fn trim(s: string) -> string effects { alloc } {
    let n = string.len(s);
    let lo: i32 = 0;
    let hi: i32 = n;
    while (lo < hi) {
        let c = string.byte_at(s, lo);
        if (c != 32) {
            if (c != 9) {
                break;
            }
        }
        lo = lo + 1;
    }
    while (hi > lo) {
        let c2 = string.byte_at(s, hi - 1);
        if (c2 != 32) {
            if (c2 != 9) {
                if (c2 != 13) {
                    if (c2 != 10) {
                        break;
                    }
                }
            }
        }
        hi = hi - 1;
    }
    return slice(s, lo, hi);
}

fn find_char(s: string, ch: i32) -> i32 {
    let n = string.len(s);
    let i: i32 = 0;
    while (i < n) {
        if (string.byte_at(s, i) == ch) {
            return i;
        }
        i = i + 1;
    }
    return -1;
}

fn strip_quotes(s: string) -> string effects { alloc } {
    let n = string.len(s);
    if (n >= 2) {
        if (string.byte_at(s, 0) == 34) {
            if (string.byte_at(s, n - 1) == 34) {
                return slice(s, 1, n - 1);
            }
        }
    }
    return s;
}

fn is_section_recipe(line: string) -> bool {
    if (strutil.starts_with(line, "[recipe.") != true) {
        return false;
    }
    let n = string.len(line);
    if (n < 10) {
        return false;
    }
    if (string.byte_at(line, n - 1) != 93) {
        return false;
    }
    return true;
}

fn recipe_name_from_section(line: string) -> string effects { alloc } {
    let n = string.len(line);
    return slice(line, 8, n - 1);
}

fn parse_string_array_body(s: string) -> Result<string, core_Err> effects { alloc, mut } {
    let t = trim(s);
    let n = string.len(t);
    if (n < 2) {
        return Ok("");
    }
    if (string.byte_at(t, 0) != 91) {
        return Err(3);
    }
    if (string.byte_at(t, n - 1) != 93) {
        return Err(3);
    }
    let inner = slice(t, 1, n - 1);
    let out = string.builder();
    let i: i32 = 0;
    let m = string.len(inner);
    let first: i32 = 1;
    while (i < m) {
        let c = string.byte_at(inner, i);
        if (c == 32) {
            i = i + 1;
        } else {
            if (c == 44) {
                i = i + 1;
            } else {
                if (c != 34) {
                    return Err(3);
                }
                i = i + 1;
                let start = i;
                while (i < m) {
                    if (string.byte_at(inner, i) == 34) {
                        break;
                    }
                    i = i + 1;
                }
                let piece = slice(inner, start, i);
                if (first == 0) {
                    out = string.append(out, "\n");
                }
                first = 0;
                out = string.append(out, piece);
                if (i < m) {
                    i = i + 1;
                }
            }
        }
    }
    return Ok(string.build(out));
}

fn load_manifest_text() -> Result<string, core_Err> effects { alloc, io } {
    if (io.file_exists("Fxrun.toml") == true) {
        return io.read_file("Fxrun.toml");
    }
    if (io.file_exists("fxrun.toml") == true) {
        return io.read_file("fxrun.toml");
    }
    // Missing manifest → exit 2 (unknown/missing), not a generic IO code.
    return Err(2);
}

fn line_in_list(list: string, name: string) -> bool effects { alloc } {
    let n = string.len(list);
    let i: i32 = 0;
    while (i < n) {
        let start = i;
        while (i < n) {
            if (string.byte_at(list, i) == 10) {
                break;
            }
            i = i + 1;
        }
        if (i > start) {
            if (eq(slice(list, start, i), name) == true) {
                return true;
            }
        }
        if (i < n) {
            i = i + 1;
        } else {
            i = n;
        }
    }
    return false;
}

fn run(list_flag: i32, dry: i32, force: i32, recipe_arg: string) -> Result<i32, core_Err> effects { alloc, mut, io } {
    region r = arena(262144);
    // Walk up to the directory that owns Fxrun.toml / fxrun.toml, then parse relative to it.
    if (fxrun_host_chdir_to_manifest() != 0) {
        return Err(2);
    }
    let text = load_manifest_text()?;
    let docs: Map<string, string> = map_new_ss();
    let deps: Map<string, string> = map_new_ss();
    let cmds: Map<string, string> = map_new_ss();
    let inputs: Map<string, string> = map_new_ss();
    let outputs: Map<string, string> = map_new_ss();
    let default_name = "";
    let section = "";
    let order_s = "";

    let n = string.len(text);
    let i: i32 = 0;
    while (i <= n) {
        let start = i;
        while (i < n) {
            if (string.byte_at(text, i) == 10) {
                break;
            }
            i = i + 1;
        }
        let line_raw = slice(text, start, i);
        if (i < n) {
            i = i + 1;
        } else {
            i = n + 1;
        }
        let line = trim(line_raw);
        let ln = string.len(line);
        if (ln == 0) {
            // blank
        } else {
            if (string.byte_at(line, 0) == 35) {
                // comment
            } else {
                if (string.byte_at(line, 0) == 91) {
                    if (eq(line, "[fxrun]") == true) {
                        section = "fxrun";
                    } else {
                        if (is_section_recipe(line) == true) {
                            section = recipe_name_from_section(line);
                            if (string.len(order_s) == 0) {
                                order_s = section;
                            } else {
                                let o2 = string.concat(order_s, ",")?;
                                order_s = string.concat(o2, section)?;
                            }
                            docs = map_insert(docs, section, "");
                            deps = map_insert(deps, section, "");
                            cmds = map_insert(cmds, section, "");
                            inputs = map_insert(inputs, section, "");
                            outputs = map_insert(outputs, section, "");
                        } else {
                            return Err(3);
                        }
                    }
                } else {
                    let eqi = find_char(line, 61);
                    if (eqi < 1) {
                        return Err(3);
                    }
                    let key = trim(slice(line, 0, eqi));
                    let val = trim(slice(line, eqi + 1, ln));
                    if (eq(section, "fxrun") == true) {
                        if (eq(key, "default") == true) {
                            default_name = strip_quotes(val);
                        }
                    } else {
                        if (string.len(section) == 0) {
                            return Err(3);
                        }
                        if (eq(key, "doc") == true) {
                            docs = map_insert(docs, section, strip_quotes(val));
                        } else {
                            if (eq(key, "depends") == true) {
                                let dep_val = parse_string_array_body(val)?;
                                deps = map_insert(deps, section, dep_val);
                            } else {
                                if (eq(key, "cmds") == true) {
                                    let cmd_val = parse_string_array_body(val)?;
                                    cmds = map_insert(cmds, section, cmd_val);
                                } else {
                                    if (eq(key, "inputs") == true) {
                                        let in_val = parse_string_array_body(val)?;
                                        inputs = map_insert(inputs, section, in_val);
                                    } else {
                                        if (eq(key, "outputs") == true) {
                                            let out_val = parse_string_array_body(val)?;
                                            outputs = map_insert(outputs, section, out_val);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    if (list_flag != 0) {
        let list_code = list_recipes(order_s, docs)?;
        return Ok(list_code);
    }

    let target = recipe_arg;
    if (string.len(target) == 0) {
        if (string.len(default_name) == 0) {
            let list_code2 = list_recipes(order_s, docs)?;
            return Ok(list_code2);
        }
        target = default_name;
    }

    if (map_contains(cmds, target) != true) {
        return Err(2);
    }

    let stack = "";
    let plan_s = build_plan("", target, deps, stack)?;
    let run_code = exec_plan(plan_s, cmds, inputs, outputs, dry, force)?;
    return Ok(run_code);
}

fn list_recipes(order_s: string, docs: Map<string, string>) -> Result<i32, core_Err> effects { alloc, mut, io } {
    let n = string.len(order_s);
    if (n == 0) {
        let _e = io.write_line("(no recipes)");
        return Ok(0);
    }
    let i: i32 = 0;
    while (i < n) {
        let start = i;
        while (i < n) {
            if (string.byte_at(order_s, i) == 44) {
                break;
            }
            i = i + 1;
        }
        let name = slice(order_s, start, i);
        let doc = map_get_or_empty(docs, name)?;
        let line_b = string.builder();
        line_b = string.append(line_b, name);
        line_b = string.append(line_b, " - ");
        line_b = string.append(line_b, doc);
        let _p = io.write_line(string.build(line_b));
        if (i < n) {
            i = i + 1;
        }
    }
    return Ok(0);
}

fn build_plan(plan_s: string, name: string, deps: Map<string, string>, stack: string) -> Result<string, core_Err> effects { alloc } {
    if (line_in_list(plan_s, name) == true) {
        return Ok(plan_s);
    }
    if (line_in_list(stack, name) == true) {
        // cycle
        return Err(4);
    }
    let stack2 = "";
    if (string.len(stack) == 0) {
        stack2 = name;
    } else {
        let sn = string.concat(stack, "\n")?;
        stack2 = string.concat(sn, name)?;
    }
    let dep_s = map_get_or_empty(deps, name)?;
    let dn = string.len(dep_s);
    let i: i32 = 0;
    while (i < dn) {
        let start = i;
        while (i < dn) {
            if (string.byte_at(dep_s, i) == 10) {
                break;
            }
            i = i + 1;
        }
        if (i > start) {
            let dname = slice(dep_s, start, i);
            plan_s = build_plan(plan_s, dname, deps, stack2)?;
        }
        if (i < dn) {
            i = i + 1;
        }
    }
    if (line_in_list(plan_s, name) == true) {
        return Ok(plan_s);
    }
    if (string.len(plan_s) > 0) {
        let with_nl = string.concat(plan_s, "\n")?;
        let with_name = string.concat(with_nl, name)?;
        return Ok(with_name);
    }
    return Ok(name);
}

fn exec_plan(plan_s: string, cmds: Map<string, string>, inputs: Map<string, string>, outputs: Map<string, string>, dry: i32, force: i32) -> Result<i32, core_Err> effects { alloc, mut, io } {
    let n = string.len(plan_s);
    let i: i32 = 0;
    while (i < n) {
        let start = i;
        while (i < n) {
            if (string.byte_at(plan_s, i) == 10) {
                break;
            }
            i = i + 1;
        }
        let name = slice(plan_s, start, i);
        let code = run_one(name, cmds, inputs, outputs, dry, force)?;
        if (code != 0) {
            return Err(code);
        }
        if (i < n) {
            i = i + 1;
        }
    }
    return Ok(0);
}

fn run_one(name: string, cmds: Map<string, string>, inputs: Map<string, string>, outputs: Map<string, string>, dry: i32, force: i32) -> Result<i32, core_Err> effects { alloc, mut, io } {
    let cmd_blob = map_get_or_empty(cmds, name)?;
    let in_blob = map_get_or_empty(inputs, name)?;
    let out_blob = map_get_or_empty(outputs, name)?;
    if (force == 0) {
        if (string.len(in_blob) > 0) {
            if (string.len(out_blob) > 0) {
                let sk = should_skip(name, in_blob, out_blob)?;
                if (sk == true) {
                    let _s = io.write_line("fxrun: skip");
                    return Ok(0);
                }
            }
        }
    }
    let cn = string.len(cmd_blob);
    if (cn == 0) {
        return Ok(0);
    }
    let j: i32 = 0;
    while (j < cn) {
        let cs = j;
        while (j < cn) {
            if (string.byte_at(cmd_blob, j) == 10) {
                break;
            }
            j = j + 1;
        }
        let cmd = slice(cmd_blob, cs, j);
        if (dry != 0) {
            let _d = io.write_line(cmd);
        } else {
            let code = fxrun_host_run_cmd(cmd);
            if (code != 0) {
                return Err(code);
            }
        }
        if (j < cn) {
            j = j + 1;
        }
    }
    if (force == 0) {
        if (string.len(in_blob) > 0) {
            if (string.len(out_blob) > 0) {
                let _w = write_stamp(name, in_blob)?;
            }
        }
    }
    return Ok(0);
}

fn fnv_mix(h: i32, b: i32) -> i32 {
    return (h ^ b) * 16777619;
}

fn hash_blob(s: string) -> i32 {
    let h: i32 = -2128831035;
    let n = string.len(s);
    let i: i32 = 0;
    while (i < n) {
        h = fnv_mix(h, string.byte_at(s, i));
        i = i + 1;
    }
    return h;
}

fn hash_inputs(in_blob: string) -> Result<i32, core_Err> effects { alloc, io } {
    let h: i32 = -2128831035;
    let n = string.len(in_blob);
    let i: i32 = 0;
    while (i < n) {
        let s = i;
        while (i < n) {
            if (string.byte_at(in_blob, i) == 10) {
                break;
            }
            i = i + 1;
        }
        if (i > s) {
            let path = slice(in_blob, s, i);
            h = fnv_mix(h, hash_blob(path));
            if (io.file_exists(path) == true) {
                let body = io.read_file(path)?;
                h = fnv_mix(h, hash_blob(body));
            }
        }
        if (i < n) {
            i = i + 1;
        }
    }
    return Ok(h);
}

fn should_skip(name: string, in_blob: string, out_blob: string) -> Result<bool, core_Err> effects { alloc, mut, io } {
    let on = string.len(out_blob);
    let i: i32 = 0;
    while (i < on) {
        let s = i;
        while (i < on) {
            if (string.byte_at(out_blob, i) == 10) {
                break;
            }
            i = i + 1;
        }
        if (i > s) {
            let path = slice(out_blob, s, i);
            if (io.file_exists(path) != true) {
                return Ok(false);
            }
        }
        if (i < on) {
            i = i + 1;
        }
    }
    let stamp_path_b = string.builder();
    stamp_path_b = string.append(stamp_path_b, ".fxrun/stamp-");
    stamp_path_b = string.append(stamp_path_b, name);
    stamp_path_b = string.append(stamp_path_b, ".txt");
    let stamp_path = string.build(stamp_path_b);
    if (io.file_exists(stamp_path) != true) {
        return Ok(false);
    }
    let prev = io.read_file(stamp_path)?;
    let hv = hash_inputs(in_blob)?;
    let want = i32_dec(hv);
    return Ok(eq(prev, want));
}

fn write_stamp(name: string, in_blob: string) -> Result<i32, core_Err> effects { alloc, mut, io } {
    let _d = fxrun_host_ensure_dir(".fxrun");
    let stamp_path_b = string.builder();
    stamp_path_b = string.append(stamp_path_b, ".fxrun/stamp-");
    stamp_path_b = string.append(stamp_path_b, name);
    stamp_path_b = string.append(stamp_path_b, ".txt");
    let stamp_path = string.build(stamp_path_b);
    let hv = hash_inputs(in_blob)?;
    let h = i32_dec(hv);
    let _w = io.write_file(stamp_path, h);
    return Ok(0);
}
