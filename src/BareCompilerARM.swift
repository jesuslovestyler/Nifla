// BareCompilerARM — the ARM door (Stone 23).
//
// `niflac --bare --arm` compiles the bare subset to a second
// target: aarch64, for QEMU's `virt` machine. The language
// the target holds is the same bare subset the x86 road
// holds — the same validator reads the program first, and
// the same shapes come out: whole numbers as the machine's
// words, text and blocks of bytes travelling as an address
// and a count, variables in frame slots, the same runaway
// guards (a million loop passes, five hundred nested
// calls), and bare's plain rule that a guard's failure
// stops the machine silently.
//
// What differs is the machine underneath, and it is named
// plainly wherever it shows:
//   - The program boots at 0x40000000 (the virt machine's
//     memory) from an ELF the loader hands it — there is
//     no multiboot here. The device tree is looked for
//     where this machine puts it: in x0 when the loader
//     hands it over (the Linux boot protocol), and at
//     address 0, where QEMU's virt machine lays it for ELF
//     kernels; the tree's magic word tells whether it is
//     there. memorysize() reads the tree's memory node;
//     when no tree is found it answers 0 (no map was
//     given) and the heap is an 8 MiB arena above the
//     kernel.
//   - `say` speaks over the PL011 serial line at
//     0x09000000 — the virt machine has no text screen —
//     and readkey() takes bytes from the same line (a byte
//     that arrived, or 0 when none is waiting), where the
//     x86 road's keys are scancodes from its keyboard.
//   - ticks() reads the machine's own free-running counter
//     (CNTPCT), scaled to a hundred ticks a second by the
//     counter's own frequency; no interrupts are involved.
//   - Floor blocks hold aarch64 assembly under the same
//     desk CONTRACT as the x86 road (Stone 24): the
//     desk's meaning is target-independent — a row of
//     handed numbers, at most one handed piece of text or
//     bytes, and a results desk a bare host does not
//     have — and only the register letters differ:
//     x19 = the handed numbers' address, x20 = how many,
//     x21/x22 = the handed text-or-bytes address and
//     count, x23/x24 = the results desk (0 here, as on
//     the x86 bare road). The block's give is what it
//     leaves in x0. The wrapper keeps x21–x25 safe
//     across the block, as the x86 wrapper keeps its
//     desk's memory side.
//   - With '--video WxHx32' the kernel sets up the
//     picture screen the virt machine honestly offers:
//     ramfb, reached through the machine's fw_cfg
//     (Stone 24). The framebuffer's address, width,
//     height and stride stand in the globals __video_fb,
//     __video_width, __video_height, __video_stride,
//     where floor blocks read them to paint; without a
//     ramfb on the machine (or room for the picture)
//     __video_fb stays 0 and there is no picture. 'say'
//     stays on the serial line either way. Only 32-bit
//     color is stood up on this target.
//   - Not stood up on this target yet, and refused in
//     plain words below rather than silently mis-built:
//     the disk tools (the virt machine has no ATA disk
//     of the kind the x86 road speaks to) and the guest
//     tools and guests themselves, and feathers.

import Foundation

// MARK: - What the ARM target does not hold yet

// Walks a program looking for the shapes Stone 23 does not
// stand up on ARM, and gives back the plain-words refusal
// for the first one found — or nil when the program is
// clear. (The validator has already proven the program is
// honest bare Nifla; this is only about the target.)
private func armRefusal(in program: [Stmt]) -> String? {
    func scanExpr(_ expr: Expr) -> String? {
        switch expr {
        case .floor(_, let args, _):
            for arg in args {
                if let found = scanExpr(arg) { return found }
            }
            return nil
        case .call(let name, let args, _):
            if name == "disksectors" || name == "diskread" || name == "diskwrite" {
                return "The disk tools are not stood up on the ARM target: the virt machine this target boots on has no ATA disk of the kind the x86 road speaks to, and '\(name)' has nothing honest to speak to yet. Build this program for the x86 target (without '--arm') to use it."
            }
            if name == "callguest" || name == "guestvalue" || name == "guestgive" {
                return "Guests are not stood up on the ARM target: the guest door belongs to the x86 host's road in this ladder, and '\(name)' has no door to speak through here yet. Build this program for the x86 target (without '--arm') to use it."
            }
            for arg in args {
                if let found = scanExpr(arg) { return found }
            }
            return nil
        case .binary(let left, _, let right, _):
            return scanExpr(left) ?? scanExpr(right)
        case .negate(let inner, _):
            return scanExpr(inner)
        case .index(let base, let index, _):
            return scanExpr(base) ?? scanExpr(index)
        case .field(let base, _, _):
            return scanExpr(base)
        case .list(let items, _):
            for item in items {
                if let found = scanExpr(item) { return found }
            }
            return nil
        case .object(let fields, _):
            for field in fields {
                if let found = scanExpr(field.value) { return found }
            }
            return nil
        case .number, .text, .boolean, .nothing, .variable:
            return nil
        }
    }
    func scanStmts(_ statements: [Stmt]) -> String? {
        for statement in statements {
            switch statement {
            case .declare(_, _, let value, _), .assign(_, let value, _), .say(let value, _), .give(let value, _), .doExpr(let value, _):
                if let found = scanExpr(value) { return found }
            case .assignTarget(let target, let value, _):
                if let found = scanExpr(target) ?? scanExpr(value) { return found }
            case .ifElse(let condition, let then, let otherwise, _):
                if let found = scanExpr(condition) { return found }
                if let found = scanStmts(then) { return found }
                if let otherwise, let found = scanStmts(otherwise) { return found }
            case .whileLoop(let condition, let body, _):
                if let found = scanExpr(condition) { return found }
                if let found = scanStmts(body) { return found }
            case .repeatLoop(let count, let body, _):
                if let found = scanExpr(count) { return found }
                if let found = scanStmts(body) { return found }
            case .forEach(_, let over, let body, _):
                if let found = scanExpr(over) { return found }
                if let found = scanStmts(body) { return found }
            case .attempt(let body, let recovery, _):
                if let found = scanStmts(body) { return found }
                if let found = scanStmts(recovery) { return found }
            case .define(_, _, _, _, let body, _):
                if let found = scanStmts(body) { return found }
            case .doCall(let name, let args, _):
                if let found = scanExpr(.call(name: name, args: args, line: 0)) { return found }
            }
        }
        return nil
    }
    return scanStmts(program)
}

// MARK: - The translator

// The aarch64 twin of BareTranslator, keeping its shapes:
// an expression's value lands in x0, and in x1 too when it
// is text or a block of bytes (x0 the address, x1 the
// count); variables live in frame slots under x29;
// arguments travel in x0...x5, in order, one word each
// (text takes two); the guards keep their x86 numbers.
struct BareTranslatorARM {
    private let functions: [String: (params: [String], giveKind: BareKind)]
    private let paramKinds: [String: [BareKind]]

    // The video request (Stone 24), when the build asked
    // for one: the mode ramfb is set up with at boot.
    var videoRequest: (width: Int, height: Int, depth: Int)? = nil

    private var code: [String] = []
    private var literals: [(label: String, bytes: [UInt8])] = []
    private var floorBlocks: [String] = []
    private var labelCounter = 0

    private var scopes: [[String: (offset: Int, kind: BareKind)]] = []
    private var nextOffset = 0
    private var currentExitLabel = "__nifla_main_exit"
    private var currentFunction: String? = nil

    init(validator: BareValidator) {
        functions = validator.functions
        paramKinds = validator.paramKinds
    }

    private mutating func freshLabel(_ base: String) -> String {
        labelCounter += 1
        return "__\(base)_\(labelCounter)"
    }

    private mutating func emit(_ line: String) {
        code.append(line)
    }

    private func kindOf(_ expr: Expr) -> BareKind {
        switch expr {
        case .number: return .number
        case .text: return .text
        case .boolean: return .boolean
        case .nothing: return .number  // refused by the validator; never emitted
        case .variable(let name, _):
            for scope in scopes.reversed() {
                if let entry = scope[name] { return entry.kind }
            }
            return .number
        case .call(let name, _, _):
            if name == "length" { return .number }
            if name == "absolute" { return .number }
            if name == "smallest" || name == "largest" { return .number }
            if name == "bitand" || name == "bitor" || name == "bitxor" { return .number }
            if name == "makebytes" { return .bytes }
            if bareOnlyTools[name] != nil { return .number }
            if guestDeskTools[name] != nil || guestDoorTools[name] != nil { return .number }
            return functions[name]?.giveKind ?? .number
        case .floor: return .number
        case .negate: return .number
        case .binary(let left, let op, let right, _):
            switch op {
            case "<", "<=", ">", ">=", "==", "!=": return .boolean
            case "+":
                if kindOf(left) == .text || kindOf(right) == .text { return .text }
                return .number
            default: return .number
            }
        case .object, .list, .field, .index:
            return .number  // refused by the validator; never emitted
        }
    }

    private func slots(for kind: BareKind) -> Int {
        (kind == .text || kind == .bytes) ? 2 : 1
    }

    private mutating func declareVar(_ name: String, kind: BareKind) -> (offset: Int, kind: BareKind) {
        nextOffset += 8 * slots(for: kind)
        let entry = (offset: nextOffset, kind: kind)
        scopes[scopes.count - 1][name] = entry
        return entry
    }

    private func lookupVar(_ name: String) -> (offset: Int, kind: BareKind) {
        for scope in scopes.reversed() {
            if let entry = scope[name] { return entry }
        }
        return (offset: 0, kind: .number)  // the checker proved it exists
    }

    // Loads a whole number into a register: a plain 'mov'
    // when the assembler's own immediates reach it, and a
    // literal-pool load for the wide ones.
    private mutating func emitLoadImm(_ register: String, _ value: Int64) {
        if value >= -65536 && value <= 65535 {
            emit("    mov \(register), #\(value)")
        } else {
            emit("    ldr \(register), =\(value)")
        }
    }

    // MARK: the whole file

    mutating func translate(_ program: [Stmt], sourceName: String) -> String {
        // Functions first, as on the x86 road: their text
        // literals gather as they are emitted, and the main
        // body follows.
        for statement in program {
            if case .define(let name, _, _, _, let body, _) = statement {
                emitFunction(name: name, body: body)
            }
        }
        emitMain(program)

        var out: [String] = []
        out.append("// A bare-metal Nifla program for aarch64 (Stone 23),")
        out.append("// compiled from \(sourceName) by niflac --bare --arm.")
        out.append("// It boots on QEMU's virt machine at 0x40000000; the")
        out.append("// device tree is looked for in x0, then at address 0,")
        out.append("// and the program speaks over the PL011 serial line")
        out.append("// at 0x09000000.")
        out.append("    .text")
        out.append("    .globl _start")
        out.append("_start:")
        // Where is the device tree? The Linux boot protocol
        // hands its address in x0; QEMU's virt machine, for
        // an ELF kernel like this one, lays the tree at
        // address 0 instead and leaves x0 at 0. Look in x0
        // first, then at address 0 — the tree's magic word
        // (0xd00dfeed, big-endian) tells whether it is
        // there. When neither holds it, __dtb keeps -1 and
        // memorysize() will answer 0: no map was given.
        out.append("    movz w11, #0xfeed")
        out.append("    movk w11, #0xd00d, lsl #16")
        out.append("    mov x9, x0")
        out.append("    cbz x9, 1f")
        out.append("    ldr w10, [x9]")
        out.append("    rev w10, w10")
        out.append("    cmp w10, w11")
        out.append("    b.eq 2f")
        out.append("1:  mov x9, #0")
        out.append("    ldr w10, [x9]")
        out.append("    rev w10, w10")
        out.append("    cmp w10, w11")
        out.append("    b.eq 2f")
        out.append("    mov x9, #-1")
        out.append("2:  ldr x10, =__dtb")
        out.append("    str x9, [x10]")
        out.append("    ldr x9, =__stack_top")
        out.append("    mov sp, x9")
        out.append("    ldr x9, =__bss_start")
        out.append("    ldr x10, =__bss_end")
        out.append("1:  cmp x9, x10")
        out.append("    b.hs 2f")
        out.append("    str xzr, [x9], #8")
        out.append("    b 1b")
        out.append("2:  bl __nifla_memory_init")
        if videoRequest != nil {
            out.append("    bl __nifla_video_init")
        }
        out.append("    bl __nifla_main")
        out.append("__halt_trap:")
        out.append("    wfe")
        out.append("    b __halt_trap")
        out.append("")
        out += runtimeLines()
        out += code
        // The floor blocks, each behind its desk — the
        // wrapper keeps the desk's memory side (x21/x22),
        // the results side (x23/x24), and one courtesy
        // register (x25) safe across the block, as the x86
        // wrapper keeps rbx/r12, r13/r14, and r15.
        for (index, asm) in floorBlocks.enumerated() {
            out.append("")
            out.append("__floor_\(index):")
            out.append("    stp x21, x22, [sp, #-16]!")
            out.append("    stp x23, x24, [sp, #-16]!")
            out.append("    str x25, [sp, #-16]!")
            out.append(asm)
            out.append("    ldr x25, [sp], #16")
            out.append("    ldp x23, x24, [sp], #16")
            out.append("    ldp x21, x22, [sp], #16")
            out.append("    ret")
        }
        if !literals.isEmpty {
            out.append("    .rodata")
            for literal in literals {
                out.append("\(literal.label):")
                let bytes = literal.bytes.map { String($0) }.joined(separator: ", ")
                out.append("    .byte \(bytes)")
            }
            out.append("")
        }
        out.append("    .bss")
        out.append("    .balign 8")
        out.append("__dtb:          .skip 8")
        out.append("__mem_total:    .skip 8")
        out.append("__heap_cursor:  .skip 8")
        out.append("__heap_limit:   .skip 8")
        out.append("__tick_divisor: .skip 8")
        out.append("__guard_depth:  .skip 8")
        out.append("__floor_inputs: .skip 128")
        out.append("__video_fb:     .skip 8")
        out.append("__video_width:  .skip 8")
        out.append("__video_height: .skip 8")
        out.append("__video_stride: .skip 8")
        out.append("__video_sel:    .skip 8")
        out.append("__video_name:   .skip 56")
        out.append("    .balign 8")
        out.append("__video_cfg:    .skip 32")
        out.append("__video_dma:    .skip 16")
        out.append("__numtext_buf:  .skip 32")
        out.append("__stack:        .skip 65536")
        out.append("__stack_top:")
        out.append("")
        return out.joined(separator: "\n") + "\n"
    }

    // MARK: the runtime

    private func runtimeLines() -> [String] {
        var out: [String] = []
        // memory_init: read the device tree (its address was
        // saved by _start) for the memory node's reg — the
        // base and size of the machine's memory — and set
        // the heap to run from the kernel's end to memory's
        // end. With no tree, memorysize() will answer 0 and
        // the heap is an 8 MiB arena above the kernel.
        out.append("__nifla_memory_init:")
        out.append("    str x30, [sp, #-16]!")
        out.append("    ldr x9, =__kernel_end")
        out.append("    add x9, x9, #15")
        out.append("    and x9, x9, #-16")
        out.append("    ldr x10, =__heap_cursor")
        out.append("    str x9, [x10]")
        out.append("    add x11, x9, #8388608")
        out.append("    ldr x10, =__heap_limit")
        out.append("    str x11, [x10]")
        out.append("    mrs x9, cntfrq_el0")
        out.append("    mov x10, #100")
        out.append("    udiv x9, x9, x10")
        out.append("    cbnz x9, 1f")
        out.append("    mov x9, #1")
        out.append("1:  ldr x10, =__tick_divisor")
        out.append("    str x9, [x10]")
        out.append("    ldr x9, =__dtb")
        out.append("    ldr x9, [x9]")
        out.append("    cmp x9, #-1")
        out.append("    b.eq 9f")
        out.append("    bl __fdt_walk")
        out.append("9:  ldr x30, [sp], #16")
        out.append("    ret")
        out.append("")
        // __fdt_walk: walk the tree's structure block.
        //   x9 = tree base. State: x14 = struct cursor,
        //   x15 = strings base, x16 = address cells,
        //   x17 = size cells, x18 = depth, x19 = inside the
        //   memory node (1) or not (0). On finding the memory
        //   node's reg, __mem_total takes its size and
        //   __heap_limit its end.
        out.append("__fdt_walk:")
        out.append("    str x30, [sp, #-16]!")
        out.append("    ldr w10, [x9, #8]")
        out.append("    rev w10, w10")
        out.append("    add x14, x9, x10")
        out.append("    ldr w10, [x9, #12]")
        out.append("    rev w10, w10")
        out.append("    add x15, x9, x10")
        out.append("    mov x16, #2")
        out.append("    mov x17, #1")
        out.append("    mov x18, #0")
        out.append("    mov x19, #0")
        out.append("__fdt_next:")
        out.append("    ldr w10, [x14], #4")
        out.append("    rev w10, w10")
        out.append("    cmp w10, #9")
        out.append("    b.eq __fdt_done")
        out.append("    cmp w10, #4")
        out.append("    b.eq __fdt_next")
        out.append("    cmp w10, #1")
        out.append("    b.eq __fdt_begin")
        out.append("    cmp w10, #2")
        out.append("    b.eq __fdt_endnode")
        out.append("    cmp w10, #3")
        out.append("    b.eq __fdt_prop")
        out.append("    b __fdt_done")
        out.append("__fdt_begin:")
        out.append("    mov x19, #0")
        out.append("    cmp x18, #1")
        out.append("    b.ne 1f")
        // A child of the root: is its name 'memory' (or
        // 'memory@...')? Six letters, then a NUL or an '@'.
        out.append("    ldrb w10, [x14]")
        out.append("    cmp w10, #109")
        out.append("    b.ne 1f")
        out.append("    ldrb w10, [x14, #1]")
        out.append("    cmp w10, #101")
        out.append("    b.ne 1f")
        out.append("    ldrb w10, [x14, #2]")
        out.append("    cmp w10, #109")
        out.append("    b.ne 1f")
        out.append("    ldrb w10, [x14, #3]")
        out.append("    cmp w10, #111")
        out.append("    b.ne 1f")
        out.append("    ldrb w10, [x14, #4]")
        out.append("    cmp w10, #114")
        out.append("    b.ne 1f")
        out.append("    ldrb w10, [x14, #5]")
        out.append("    cmp w10, #121")
        out.append("    b.ne 1f")
        out.append("    ldrb w10, [x14, #6]")
        out.append("    cmp w10, #64")
        out.append("    b.eq 2f")
        out.append("    cmp w10, #0")
        out.append("    b.ne 1f")
        out.append("2:  mov x19, #1")
        out.append("1:  add x18, x18, #1")
        // Skip the node's name: NUL-terminated, 4-aligned.
        out.append("    mov x10, x14")
        out.append("3:  ldrb w11, [x10], #1")
        out.append("    cbnz w11, 3b")
        out.append("    sub x14, x10, x9")
        out.append("    add x14, x14, #3")
        out.append("    and x14, x14, #-4")
        out.append("    add x14, x14, x9")
        out.append("    b __fdt_next")
        out.append("__fdt_endnode:")
        out.append("    sub x18, x18, #1")
        out.append("    cmp x18, #1")
        out.append("    b.gt 1f")
        out.append("    mov x19, #0")
        out.append("1:  b __fdt_next")
        out.append("__fdt_prop:")
        out.append("    ldr w20, [x14], #4")
        out.append("    rev w20, w20")
        out.append("    ldr w21, [x14], #4")
        out.append("    rev w21, w21")
        out.append("    add x22, x15, x21")
        out.append("    cmp x18, #1")
        out.append("    b.ne 3f")
        // At the root: '#address-cells' / '#size-cells'.
        out.append("    mov x0, x22")
        out.append("    ldr x1, =__fdt_addr_cells")
        out.append("    mov x2, #14")
        out.append("    bl __fdt_name_eq")
        out.append("    cbz x0, 1f")
        out.append("    ldr w10, [x14]")
        out.append("    rev w10, w10")
        out.append("    mov x16, x10")
        out.append("    b 3f")
        out.append("1:  mov x0, x22")
        out.append("    ldr x1, =__fdt_size_cells")
        out.append("    mov x2, #11")
        out.append("    bl __fdt_name_eq")
        out.append("    cbz x0, 3f")
        out.append("    ldr w10, [x14]")
        out.append("    rev w10, w10")
        out.append("    mov x17, x10")
        out.append("    b 3f")
        out.append("3:  cmp x19, #1")
        out.append("    b.ne 4f")
        out.append("    mov x0, x22")
        out.append("    ldr x1, =__fdt_reg")
        out.append("    mov x2, #3")
        out.append("    bl __fdt_name_eq")
        out.append("    cbz x0, 4f")
        // The memory node's reg: address cells, then size
        // cells, each a run of big-endian 32-bit cells.
        out.append("    mov x10, x14")
        out.append("    mov x11, #0")
        out.append("    mov x12, x16")
        out.append("5:  cbz x12, 6f")
        out.append("    ldr w13, [x10], #4")
        out.append("    rev w13, w13")
        out.append("    lsl x11, x11, #32")
        out.append("    orr x11, x11, x13")
        out.append("    sub x12, x12, #1")
        out.append("    b 5b")
        out.append("6:  mov x12, x17")
        out.append("    mov x13, #0")
        out.append("7:  cbz x12, 8f")
        out.append("    ldr w23, [x10], #4")
        out.append("    rev w23, w23")
        out.append("    lsl x13, x13, #32")
        out.append("    orr x13, x13, x23")
        out.append("    sub x12, x12, #1")
        out.append("    b 7b")
        out.append("8:  ldr x10, =__mem_total")
        out.append("    str x13, [x10]")
        out.append("    add x11, x11, x13")
        out.append("    ldr x10, =__heap_limit")
        out.append("    str x11, [x10]")
        out.append("4:  add x14, x14, x20")
        out.append("    add x14, x14, #3")
        out.append("    and x14, x14, #-4")
        out.append("    b __fdt_next")
        out.append("__fdt_done:")
        out.append("    ldr x30, [sp], #16")
        out.append("    ret")
        out.append("")
        // __fdt_name_eq: x0 = candidate (NUL-terminated),
        // x1 = the name it must equal, x2 = the name's
        // length. Gives back 1 when the candidate is exactly
        // that name, else 0.
        out.append("__fdt_name_eq:")
        out.append("    mov x12, #0")
        out.append("1:  cmp x12, x2")
        out.append("    b.hs 2f")
        out.append("    ldrb w10, [x0, x12]")
        out.append("    ldrb w11, [x1, x12]")
        out.append("    cmp w10, w11")
        out.append("    b.ne 3f")
        out.append("    add x12, x12, #1")
        out.append("    b 1b")
        out.append("2:  ldrb w10, [x0, x2]")
        out.append("    cbz w10, 4f")
        out.append("3:  mov x0, #0")
        out.append("    ret")
        out.append("4:  mov x0, #1")
        out.append("    ret")
        out.append("    .rodata")
        out.append("__fdt_addr_cells: .asciz \"#address-cells\"")
        out.append("__fdt_size_cells: .asciz \"#size-cells\"")
        out.append("__fdt_reg:        .asciz \"reg\"")
        out.append("    .text")
        out.append("")
        // alloc: a count in x0 becomes a block — its address
        // in x0, its count in x1. The block starts zeroed.
        out.append("__nifla_alloc:")
        out.append("    ldr x9, =16777216")
        out.append("    cmp x0, x9")
        out.append("    b.hi __halt_trap")
        out.append("    mov x1, x0")
        out.append("    add x0, x0, #15")
        out.append("    and x0, x0, #-16")
        out.append("    ldr x9, =__heap_cursor")
        out.append("    ldr x10, [x9]")
        out.append("    add x11, x10, x0")
        out.append("    ldr x12, =__heap_limit")
        out.append("    ldr x12, [x12]")
        out.append("    cmp x11, x12")
        out.append("    b.hi __halt_trap")
        out.append("    str x11, [x9]")
        out.append("    mov x12, x10")
        out.append("    mov x13, x0")
        out.append("1:  cbz x13, 2f")
        out.append("    str xzr, [x12], #8")
        out.append("    sub x13, x13, #8")
        out.append("    b 1b")
        out.append("2:  mov x0, x10")
        out.append("    ret")
        out.append("")
        // numtext: a number in x0 becomes its written form —
        // address in x0, count in x1, in a fresh block.
        out.append("__nifla_numtext:")
        out.append("    stp x29, x30, [sp, #-16]!")
        out.append("    mov x29, sp")
        out.append("    mov x9, x0")
        out.append("    mov x10, #0")
        out.append("    cmp x9, #0")
        out.append("    b.ge 1f")
        out.append("    mov x10, #1")
        out.append("    neg x9, x9")
        out.append("1:  ldr x11, =__numtext_buf")
        out.append("    add x11, x11, #32")
        out.append("    mov x12, x11")
        out.append("    mov x13, #10")
        out.append("2:  udiv x14, x9, x13")
        out.append("    msub x15, x14, x13, x9")
        out.append("    add x15, x15, #48")
        out.append("    sub x12, x12, #1")
        out.append("    strb w15, [x12]")
        out.append("    mov x9, x14")
        out.append("    cbnz x9, 2b")
        out.append("    cbz x10, 3f")
        out.append("    sub x12, x12, #1")
        out.append("    mov w15, #45")
        out.append("    strb w15, [x12]")
        out.append("3:  sub x0, x11, x12")
        out.append("    str x12, [sp, #-16]!")
        out.append("    bl __nifla_alloc")
        out.append("    ldr x13, [sp], #16")
        out.append("    mov x14, x0")
        out.append("    mov x15, x1")
        out.append("4:  cbz x15, 5f")
        out.append("    ldrb w16, [x13], #1")
        out.append("    strb w16, [x14], #1")
        out.append("    sub x15, x15, #1")
        out.append("    b 4b")
        out.append("5:  ldp x29, x30, [sp], #16")
        out.append("    ret")
        out.append("")
        // join: two pieces of text (x0/x1 and x2/x3) laid
        // side by side in a fresh block; the joined text
        // comes back in x0/x1.
        out.append("__nifla_join:")
        out.append("    stp x29, x30, [sp, #-16]!")
        out.append("    mov x29, sp")
        out.append("    str x0, [sp, #-16]!")
        out.append("    str x1, [sp, #-16]!")
        out.append("    str x2, [sp, #-16]!")
        out.append("    str x3, [sp, #-16]!")
        out.append("    add x0, x1, x3")
        out.append("    bl __nifla_alloc")
        out.append("    ldr x16, [sp], #16")
        out.append("    ldr x15, [sp], #16")
        out.append("    ldr x14, [sp], #16")
        out.append("    ldr x13, [sp], #16")
        // x13 = left ptr, x14 = left len, x15 = right ptr,
        // x16 = right len; x0/x1 = the new block and its len.
        out.append("    mov x17, x0")
        out.append("    mov x9, x14")
        out.append("    mov x10, x13")
        out.append("1:  cbz x9, 2f")
        out.append("    ldrb w11, [x10], #1")
        out.append("    strb w11, [x17], #1")
        out.append("    sub x9, x9, #1")
        out.append("    b 1b")
        out.append("2:  mov x9, x16")
        out.append("    mov x10, x15")
        out.append("3:  cbz x9, 4f")
        out.append("    ldrb w11, [x10], #1")
        out.append("    strb w11, [x17], #1")
        out.append("    sub x9, x9, #1")
        out.append("    b 3b")
        out.append("4:  ldp x29, x30, [sp], #16")
        out.append("    ret")
        out.append("")
        // text_eq: two pieces of text (x0/x1 and x2/x3);
        // gives back 1 in x0 when they are the same words.
        out.append("__nifla_text_eq:")
        out.append("    cmp x1, x3")
        out.append("    b.ne 3f")
        out.append("    mov x9, #0")
        out.append("1:  cmp x9, x1")
        out.append("    b.hs 2f")
        out.append("    ldrb w10, [x0, x9]")
        out.append("    ldrb w11, [x2, x9]")
        out.append("    cmp w10, w11")
        out.append("    b.ne 3f")
        out.append("    add x9, x9, #1")
        out.append("    b 1b")
        out.append("2:  mov x0, #1")
        out.append("    ret")
        out.append("3:  mov x0, #0")
        out.append("    ret")
        out.append("")
        // say over the PL011: say_text writes a piece of
        // text (x0 the address, x1 the count); say_newline
        // writes the newline byte. The transmitter is polled
        // — the flag register's fifth bit says its FIFO is
        // full.
        out.append("__nifla_say_text:")
        out.append("    mov x9, x0")
        out.append("    mov x10, x1")
        out.append("    mov x11, #0")
        out.append("    ldr x12, =0x09000000")
        out.append("1:  cmp x11, x10")
        out.append("    b.hs 3f")
        out.append("    ldrb w13, [x9, x11]")
        out.append("2:  ldr w14, [x12, #24]")
        out.append("    tst w14, #32")
        out.append("    b.ne 2b")
        out.append("    str w13, [x12]")
        out.append("    add x11, x11, #1")
        out.append("    b 1b")
        out.append("3:  ret")
        out.append("__nifla_say_newline:")
        out.append("    ldr x12, =0x09000000")
        out.append("    mov w13, #10")
        out.append("2:  ldr w14, [x12, #24]")
        out.append("    tst w14, #32")
        out.append("    b.ne 2b")
        out.append("    str w13, [x12]")
        out.append("    ret")
        out.append("")
        // The machine's own reads: ticks from the
        // free-running counter, scaled by its frequency to
        // a hundred a second; waittick sleeps one tick;
        // readkey takes a byte off the serial line (0 when
        // none is waiting); memorysize answers the device
        // tree's reckoning.
        out.append("__nifla_ticks:")
        out.append("    mrs x0, cntpct_el0")
        out.append("    ldr x9, =__tick_divisor")
        out.append("    ldr x9, [x9]")
        out.append("    udiv x0, x0, x9")
        out.append("    ret")
        out.append("__nifla_waittick:")
        out.append("    mrs x9, cntpct_el0")
        out.append("    ldr x10, =__tick_divisor")
        out.append("    ldr x10, [x10]")
        out.append("    add x9, x9, x10")
        out.append("1:  mrs x11, cntpct_el0")
        out.append("    cmp x11, x9")
        out.append("    b.lo 1b")
        out.append("    mrs x0, cntpct_el0")
        out.append("    udiv x0, x0, x10")
        out.append("    ret")
        out.append("__nifla_readkey:")
        out.append("    ldr x9, =0x09000000")
        out.append("    ldr w10, [x9, #24]")
        out.append("    tst w10, #16")
        out.append("    b.ne 1f")
        out.append("    ldr w0, [x9]")
        out.append("    and x0, x0, #255")
        out.append("    ret")
        out.append("1:  mov x0, #0")
        out.append("    ret")
        out.append("__nifla_memorysize:")
        out.append("    ldr x9, =__mem_total")
        out.append("    ldr x0, [x9]")
        out.append("    ret")
        out.append("")
        if let video = videoRequest {
            out += videoLines(video)
        }
        return out
    }

    // The picture screen (Stone 24): ramfb over the
    // machine's fw_cfg. The kernel walks the fw_cfg file
    // directory (its selector register takes a big-endian
    // key at +8; the data register at +0 hands the file's
    // bytes one by one) looking for 'etc/ramfb'; takes a
    // framebuffer from the heap; and writes the ramfb
    // config through the fw_cfg DMA door (the plain data
    // writes did not apply the config on this bench's
    // QEMU — the DMA door is the one that stands, proven
    // by the Stone 24 spike). Any failure along the way —
    // no ramfb file, no room, a DMA error — leaves
    // __video_fb at 0: no picture, said plainly by the
    // globals rather than by stopping the machine. The
    // routine is written flat, with no calls, so the
    // return address is never in danger.
    private func videoLines(_ video: (width: Int, height: Int, depth: Int)) -> [String] {
        let stride = video.width * 4
        let size = stride * video.height
        var out: [String] = []
        out.append("__nifla_video_init:")
        out.append("    ldr x21, =0x09020000")
        out.append("    mov w9, #0x1900")
        out.append("    strh w9, [x21, #8]")
        out.append("    mov x24, #0")
        out.append("    mov x25, #4")
        out.append("__video_count:")
        out.append("    ldrb w9, [x21]")
        out.append("    lsl x24, x24, #8")
        out.append("    orr x24, x24, x9")
        out.append("    sub x25, x25, #1")
        out.append("    cbnz x25, __video_count")
        out.append("__video_entry:")
        out.append("    cbz x24, __video_none")
        out.append("    mov x25, #4")
        out.append("__video_skip_size:")
        out.append("    ldrb w9, [x21]")
        out.append("    sub x25, x25, #1")
        out.append("    cbnz x25, __video_skip_size")
        out.append("    ldrb w9, [x21]")
        out.append("    lsl x26, x9, #8")
        out.append("    ldrb w9, [x21]")
        out.append("    orr x26, x26, x9")
        out.append("    mov x25, #2")
        out.append("__video_skip_res:")
        out.append("    ldrb w9, [x21]")
        out.append("    sub x25, x25, #1")
        out.append("    cbnz x25, __video_skip_res")
        out.append("    ldr x27, =__video_name")
        out.append("    mov x25, #0")
        out.append("__video_name_in:")
        out.append("    ldrb w9, [x21]")
        out.append("    strb w9, [x27, x25]")
        out.append("    add x25, x25, #1")
        out.append("    cmp x25, #56")
        out.append("    b.lo __video_name_in")
        out.append("    ldr x28, =__ramfb_name")
        out.append("    mov x25, #0")
        out.append("__video_cmp:")
        out.append("    ldrb w9, [x28, x25]")
        out.append("    ldrb w10, [x27, x25]")
        out.append("    cmp w9, w10")
        out.append("    b.ne __video_next")
        out.append("    cbz w9, __video_found")
        out.append("    add x25, x25, #1")
        out.append("    b __video_cmp")
        out.append("__video_next:")
        out.append("    sub x24, x24, #1")
        out.append("    b __video_entry")
        out.append("__video_found:")
        out.append("    ldr x9, =__video_sel")
        out.append("    str x26, [x9]")
        // The framebuffer: the heap cursor, page-aligned,
        // checked against the heap's end before it is
        // committed — no room means no picture.
        out.append("    ldr x9, =__heap_cursor")
        out.append("    ldr x10, [x9]")
        out.append("    add x10, x10, #4095")
        out.append("    and x10, x10, #-4096")
        out.append("    ldr x11, =\(size)")
        out.append("    add x12, x10, x11")
        out.append("    ldr x13, =__heap_limit")
        out.append("    ldr x13, [x13]")
        out.append("    cmp x12, x13")
        out.append("    b.hi __video_none")
        out.append("    str x12, [x9]")
        out.append("    ldr x9, =__video_fb")
        out.append("    str x10, [x9]")
        out.append("    ldr x9, =__video_width")
        out.append("    ldr x10, =\(video.width)")
        out.append("    str x10, [x9]")
        out.append("    ldr x9, =__video_height")
        out.append("    ldr x10, =\(video.height)")
        out.append("    str x10, [x9]")
        out.append("    ldr x9, =__video_stride")
        out.append("    ldr x10, =\(stride)")
        out.append("    str x10, [x9]")
        // The config, big-endian fields, in __video_cfg.
        out.append("    ldr x27, =__video_cfg")
        out.append("    ldr x9, =__video_fb")
        out.append("    ldr x9, [x9]")
        out.append("    rev x9, x9")
        out.append("    str x9, [x27]")
        out.append("    ldr w9, =0x34325258")
        out.append("    rev w9, w9")
        out.append("    str w9, [x27, #8]")
        out.append("    str wzr, [x27, #12]")
        out.append("    ldr w9, =\(video.width)")
        out.append("    rev w9, w9")
        out.append("    str w9, [x27, #16]")
        out.append("    ldr w9, =\(video.height)")
        out.append("    rev w9, w9")
        out.append("    str w9, [x27, #20]")
        out.append("    ldr w9, =\(stride)")
        out.append("    rev w9, w9")
        out.append("    str w9, [x27, #24]")
        // The DMA access in __video_dma, and the trigger:
        // the access's address as two big-endian words,
        // high at +16 first, then low at +20.
        out.append("    ldr x27, =__video_dma")
        out.append("    ldr x9, =__video_sel")
        out.append("    ldr x9, [x9]")
        out.append("    lsl x9, x9, #16")
        out.append("    orr x9, x9, #24")
        out.append("    rev w9, w9")
        out.append("    str w9, [x27]")
        out.append("    mov w9, #28")
        out.append("    rev w9, w9")
        out.append("    str w9, [x27, #4]")
        out.append("    ldr x9, =__video_cfg")
        out.append("    rev x9, x9")
        out.append("    str x9, [x27, #8]")
        out.append("    mov x9, x27")
        out.append("    lsr x10, x9, #32")
        out.append("    rev w10, w10")
        out.append("    str w10, [x21, #16]")
        out.append("    rev w9, w9")
        out.append("    str w9, [x21, #20]")
        out.append("    ldr x11, =100000000")
        out.append("__video_poll:")
        out.append("    ldr w9, [x27]")
        out.append("    rev w9, w9")
        out.append("    cbz w9, __video_done")
        out.append("    tst w9, #1")
        out.append("    b.ne __video_fail")
        out.append("    sub x11, x11, #1")
        out.append("    cbnz x11, __video_poll")
        out.append("__video_fail:")
        out.append("    ldr x9, =__video_fb")
        out.append("    str xzr, [x9]")
        out.append("__video_done:")
        out.append("__video_none:")
        out.append("    ret")
        out.append("    .rodata")
        out.append("__ramfb_name: .asciz \"etc/ramfb\"")
        out.append("    .text")
        out.append("")
        return out
    }

    // MARK: functions and the main body

    private mutating func emitFunction(name: String, body: [Stmt]) {
        let info = functions[name]!
        scopes = [[:]]
        nextOffset = 0
        currentFunction = name
        currentExitLabel = "__fn_\(name)_exit"
        // Parameters arrive in registers, in order — x0, x1,
        // x2, x3, x4, x5, one word each (text takes two).
        let registers = ["x0", "x1", "x2", "x3", "x4", "x5"]
        var paramStores: [String] = []
        var registerIndex = 0
        for (index, param) in info.params.enumerated() {
            let kind = paramKinds[name]![index]
            let entry = declareVar(param, kind: kind == .unknown ? .number : kind)
            for slot in 0..<slots(for: entry.kind) {
                let offset = entry.offset - 8 * (slots(for: entry.kind) - 1 - slot)
                paramStores.append("    str \(registers[registerIndex]), [x29, #-\(offset)]")
                registerIndex += 1
            }
        }
        let bodyStart = code.count
        for statement in body {
            emitStatement(statement)
        }
        let bodyLines = Array(code[bodyStart...])
        code = Array(code[..<bodyStart])
        let frameSize = (nextOffset + 15) / 16 * 16
        emit("__fn_\(name):")
        emit("    stp x29, x30, [sp, #-16]!")
        emit("    mov x29, sp")
        if frameSize > 0 { emit("    sub sp, sp, #\(frameSize)") }
        emit("    ldr x9, =__guard_depth")
        emit("    ldr x10, [x9]")
        emit("    cmp x10, #500")
        emit("    b.hs __halt_trap")
        emit("    add x10, x10, #1")
        emit("    str x10, [x9]")
        for line in paramStores { emit(line) }
        code += bodyLines
        emit("    mov x0, #0")
        emit("    mov x1, #0")
        emit("\(currentExitLabel):")
        emit("    ldr x9, =__guard_depth")
        emit("    ldr x10, [x9]")
        emit("    sub x10, x10, #1")
        emit("    str x10, [x9]")
        emit("    mov sp, x29")
        emit("    ldp x29, x30, [sp], #16")
        emit("    ret")
        emit("")
        scopes = []
        currentFunction = nil
    }

    private mutating func emitMain(_ program: [Stmt]) {
        scopes = [[:]]
        nextOffset = 0
        currentFunction = nil
        currentExitLabel = "__nifla_main_exit"
        let bodyStart = code.count
        for statement in program {
            if case .define = statement { continue }
            emitStatement(statement)
        }
        let bodyLines = Array(code[bodyStart...])
        code = Array(code[..<bodyStart])
        let frameSize = (nextOffset + 15) / 16 * 16
        emit("__nifla_main:")
        emit("    stp x29, x30, [sp, #-16]!")
        emit("    mov x29, sp")
        if frameSize > 0 { emit("    sub sp, sp, #\(frameSize)") }
        code += bodyLines
        emit("\(currentExitLabel):")
        emit("    mov sp, x29")
        emit("    ldp x29, x30, [sp], #16")
        emit("    ret")
        emit("")
        scopes = []
    }

    // MARK: statements

    private mutating func emitBlock(_ statements: [Stmt]) {
        scopes.append([:])
        for statement in statements {
            emitStatement(statement)
        }
        scopes.removeLast()
    }

    // One pass of one loop, counted in that loop's own frame
    // slot (Stone 33): the million-pass guard stands over one
    // loop's run, not over the whole program, so each loop is
    // given a fresh count of its own as it starts.
    private mutating func emitGuardTick(_ passEntry: (offset: Int, kind: BareKind)) {
        emit("    ldr x10, [x29, #-\(passEntry.offset)]")
        emit("    add x10, x10, #1")
        emit("    str x10, [x29, #-\(passEntry.offset)]")
        emit("    ldr x11, =1000000")
        emit("    cmp x10, x11")
        emit("    b.gt __halt_trap")
    }

    private mutating func emitStatement(_ statement: Stmt) {
        switch statement {
        case .declare(let name, _, let value, _):
            let kind = kindOf(value)
            emitExpr(value)
            let entry = declareVar(name, kind: kind)
            emitStore(entry)

        case .assign(let name, let value, _):
            emitExpr(value)
            emitStore(lookupVar(name))

        case .assignTarget(let target, let value, _):
            // Setting a byte in a block of bytes — the one
            // setting-by-place bare metal has. A pick outside
            // the block, or a value that isn't a byte, stops
            // the machine.
            if case .index(let base, let index, _) = target {
                emitExpr(base)
                emit("    str x0, [sp, #-16]!")
                emit("    str x1, [sp, #-16]!")
                emitExpr(index)
                emit("    str x0, [sp, #-16]!")
                emitExpr(value)
                emit("    mov x8, x0")
                emit("    ldr x0, [sp], #16")
                emit("    ldr x1, [sp], #16")
                emit("    ldr x2, [sp], #16")
                // x2 the block's address, x1 its count, x0
                // the index, x8 the value.
                emit("    cmp x0, x1")
                emit("    b.hs __halt_trap")
                emit("    cmp x8, #255")
                emit("    b.hi __halt_trap")
                emit("    strb w8, [x2, x0]")
            } else {
                emit("    b __halt_trap")  // fields: refused by the validator
            }

        case .say(let value, _):
            emitExpr(value)
            if kindOf(value) == .number {
                emit("    bl __nifla_numtext")
            }
            emit("    bl __nifla_say_text")
            emit("    bl __nifla_say_newline")

        case .forEach, .attempt, .define:
            // Refused by the validator; never emitted.
            emit("    b __halt_trap")

        case .ifElse(let condition, let then, let otherwise, _):
            let elseLabel = freshLabel("else")
            let endLabel = freshLabel("endif")
            emitExpr(condition)
            emit("    cbz x0, \(otherwise != nil ? elseLabel : endLabel)")
            emitBlock(then)
            if let otherwise {
                emit("    b \(endLabel)")
                emit("\(elseLabel):")
                emitBlock(otherwise)
            }
            emit("\(endLabel):")

        case .whileLoop(let condition, let body, _):
            let passEntry = declareVar(freshLabel("guard_passes"), kind: .number)
            let topLabel = freshLabel("while")
            let endLabel = freshLabel("endwhile")
            emit("    str xzr, [x29, #-\(passEntry.offset)]")
            emit("\(topLabel):")
            emitExpr(condition)
            emit("    cbz x0, \(endLabel)")
            emitGuardTick(passEntry)
            emitBlock(body)
            emit("    b \(topLabel)")
            emit("\(endLabel):")

        case .repeatLoop(let count, let body, _):
            let countEntry = declareVar(freshLabel("repeat_count"), kind: .number)
            let counterEntry = declareVar(freshLabel("repeat_done"), kind: .number)
            let passEntry = declareVar(freshLabel("guard_passes"), kind: .number)
            emitExpr(count)
            emit("    str x0, [x29, #-\(countEntry.offset)]")
            emit("    cmp x0, #0")
            emit("    b.lt __halt_trap")
            emit("    str xzr, [x29, #-\(counterEntry.offset)]")
            emit("    str xzr, [x29, #-\(passEntry.offset)]")
            let topLabel = freshLabel("repeat")
            let endLabel = freshLabel("endrepeat")
            emit("\(topLabel):")
            emit("    ldr x0, [x29, #-\(counterEntry.offset)]")
            emit("    ldr x9, [x29, #-\(countEntry.offset)]")
            emit("    cmp x0, x9")
            emit("    b.hs \(endLabel)")
            emitGuardTick(passEntry)
            emitBlock(body)
            emit("    ldr x0, [x29, #-\(counterEntry.offset)]")
            emit("    add x0, x0, #1")
            emit("    str x0, [x29, #-\(counterEntry.offset)]")
            emit("    b \(topLabel)")
            emit("\(endLabel):")

        case .give(let value, _):
            emitExpr(value)
            emit("    b \(currentExitLabel)")

        case .doCall(let name, let args, let line):
            emitCall(name: name, args: args, line: line)

        case .doExpr(let expr, _):
            emitExpr(expr)
        }
    }

    // Stores the value in x0 (and x1, for a two-word value)
    // into a variable's slot(s) — the same layout as the
    // x86 road: the address word in the higher slot, the
    // count word in the lower.
    private mutating func emitStore(_ entry: (offset: Int, kind: BareKind)) {
        if slots(for: entry.kind) == 2 {
            emit("    str x0, [x29, #-\(entry.offset - 8)]")
            emit("    str x1, [x29, #-\(entry.offset)]")
        } else {
            emit("    str x0, [x29, #-\(entry.offset)]")
        }
    }

    // MARK: expressions — the value lands in x0, and in x1
    // too when it is text (x0 the address, x1 the count).

    private mutating func emitExpr(_ expr: Expr) {
        switch expr {
        case .number(let value, _):
            emitLoadImm("x0", Int64(value))

        case .text(let text, _):
            let label = "__text_\(literals.count)"
            literals.append((label: label, bytes: Array(text.utf8)))
            emit("    ldr x0, =\(label)")
            emitLoadImm("x1", Int64(Array(text.utf8).count))

        case .boolean(let flag, _):
            emit("    mov x0, #\(flag ? 1 : 0)")

        case .nothing:
            emit("    b __halt_trap")  // refused by the validator; never emitted

        case .variable(let name, _):
            let entry = lookupVar(name)
            if slots(for: entry.kind) == 2 {
                emit("    ldr x0, [x29, #-\(entry.offset - 8)]")
                emit("    ldr x1, [x29, #-\(entry.offset)]")
            } else {
                emit("    ldr x0, [x29, #-\(entry.offset)]")
            }

        case .call(let name, let args, let line):
            emitCall(name: name, args: args, line: line)

        case .floor(let asm, let args, _):
            // The desk, in this target's letters (Stone
            // 24): the handed numbers are laid in the
            // __floor_inputs row as they are worked out —
            // x19 will point at the row and x20 say how
            // many — and a handed piece of text or bytes
            // crosses in x21/x22. The results desk (x23/
            // x24) is 0: a bare host has none, as on x86.
            // The block's give is what it leaves in x0.
            let index = floorBlocks.count
            floorBlocks.append(asm)
            var numberIndex = 0
            var hasText = false
            for arg in args {
                if slots(for: kindOf(arg)) == 2 {
                    emitExpr(arg)
                    emit("    mov x21, x0")
                    emit("    mov x22, x1")
                    hasText = true
                } else {
                    emitExpr(arg)
                    emit("    ldr x9, =__floor_inputs")
                    emit("    str x0, [x9, #\(8 * numberIndex)]")
                    numberIndex += 1
                }
            }
            emit("    ldr x19, =__floor_inputs")
            emitLoadImm("x20", Int64(numberIndex))
            if !hasText {
                emit("    mov x21, #0")
                emit("    mov x22, #0")
            }
            emit("    mov x23, #0")
            emit("    mov x24, #0")
            emit("    bl __floor_\(index)")

        case .negate(let inner, _):
            emitExpr(inner)
            emit("    neg x0, x0")

        case .binary(let left, let op, let right, _):
            if op == "+" && (kindOf(left) == .text || kindOf(right) == .text) {
                // Joining: each side is made into text — a
                // number by its digits — and __nifla_join
                // lays the two side by side in a fresh block.
                emitExpr(left)
                if kindOf(left) == .number {
                    emit("    bl __nifla_numtext")
                }
                emit("    str x0, [sp, #-16]!")
                emit("    str x1, [sp, #-16]!")
                emitExpr(right)
                if kindOf(right) == .number {
                    emit("    bl __nifla_numtext")
                }
                emit("    mov x2, x0")
                emit("    mov x3, x1")
                emit("    ldr x1, [sp], #16")
                emit("    ldr x0, [sp], #16")
                emit("    bl __nifla_join")
                return
            }
            if (op == "==" || op == "!=") && (kindOf(left) == .text || kindOf(right) == .text) {
                emitExpr(left)
                emit("    str x0, [sp, #-16]!")
                emit("    str x1, [sp, #-16]!")
                emitExpr(right)
                emit("    mov x3, x1")
                emit("    mov x2, x0")
                emit("    ldr x1, [sp], #16")
                emit("    ldr x0, [sp], #16")
                emit("    bl __nifla_text_eq")
                if op == "!=" { emit("    eor x0, x0, #1") }
                return
            }
            emitExpr(left)
            emit("    str x0, [sp, #-16]!")
            emitExpr(right)
            emit("    mov x2, x0")
            emit("    ldr x0, [sp], #16")
            switch op {
            case "+": emit("    add x0, x0, x2")
            case "-": emit("    sub x0, x0, x2")
            case "*": emit("    mul x0, x0, x2")
            case "/":
                emit("    cbz x2, __halt_trap")
                emit("    sdiv x0, x0, x2")
            case "<": emitCompare("lt")
            case "<=": emitCompare("le")
            case ">": emitCompare("gt")
            case ">=": emitCompare("ge")
            case "==": emitCompare("eq")
            case "!=": emitCompare("ne")
            default: emit("    b __halt_trap")
            }

        case .index(let base, let index, _):
            // Reading a byte from a block of bytes — the one
            // indexing bare metal has. A pick outside the
            // block stops the machine.
            emitExpr(base)
            emit("    str x0, [sp, #-16]!")
            emit("    str x1, [sp, #-16]!")
            emitExpr(index)
            emit("    ldr x1, [sp], #16")
            emit("    ldr x2, [sp], #16")
            // x2 the block's address, x1 its count, x0 the
            // index.
            emit("    cmp x0, x1")
            emit("    b.hs __halt_trap")
            emit("    ldrb w0, [x2, x0]")

        case .object, .list, .field:
            emit("    b __halt_trap")  // refused by the validator
        }
    }

    private mutating func emitCompare(_ condition: String) {
        emit("    cmp x0, x2")
        emit("    cset x0, \(condition)")
    }

    // A call: values are worked out in order, stacked, and
    // popped into the registers — x0...x5 — then the
    // function is called. 'length' is the one tool whose
    // answer is already in hand: the text is in x0/x1, so
    // its count is the answer.
    private mutating func emitCall(name: String, args: [Expr], line: Int) {
        if name == "length" {
            emitExpr(args[0])
            emit("    mov x0, x1")
            return
        }
        if name == "absolute" {
            // Stone 34: the value is in x0; a value
            // below zero is negated, the rest are left
            // as they stand.
            emitExpr(args[0])
            let done = freshLabel("absolute_done")
            emit("    cmp x0, xzr")
            emit("    b.ge \(done)")
            emit("    neg x0, x0")
            emit("\(done):")
            return
        }
        if name == "smallest" || name == "largest" {
            // Stone 35: the first value is kept on the
            // stack while the second is worked out; the
            // comparison chooses which of the two the
            // answer is.
            emitExpr(args[0])
            emit("    str x0, [sp, #-16]!")
            emitExpr(args[1])
            emit("    mov x2, x0")
            emit("    ldr x0, [sp], #16")
            let done = freshLabel("choose_done")
            emit("    cmp x0, x2")
            emit(name == "smallest" ? "    b.le \(done)" : "    b.ge \(done)")
            emit("    mov x0, x2")
            emit("\(done):")
            return
        }
        if name == "bitand" || name == "bitor" || name == "bitxor" {
            // Stone 36: the bit words on the machine's
            // own words — one instruction each, once
            // both operands are in hand. A negative
            // operand stops the machine: the hosted
            // doors refuse one in plain words, and
            // stopping is bare metal's way of refusing.
            emitExpr(args[0])
            emit("    str x0, [sp, #-16]!")
            emitExpr(args[1])
            emit("    mov x2, x0")
            emit("    ldr x0, [sp], #16")
            emit("    cmp x0, xzr")
            emit("    b.lt __halt_trap")
            emit("    cmp x2, xzr")
            emit("    b.lt __halt_trap")
            switch name {
            case "bitand": emit("    and x0, x0, x2")
            case "bitor": emit("    orr x0, x0, x2")
            default: emit("    eor x0, x0, x2")
            }
            return
        }
        if name == "makebytes" {
            emitExpr(args[0])
            emit("    bl __nifla_alloc")
            return
        }
        if name == "memorysize" {
            emit("    bl __nifla_memorysize")
            return
        }
        if name == "ticks" {
            emit("    bl __nifla_ticks")
            return
        }
        if name == "waittick" {
            emit("    bl __nifla_waittick")
            return
        }
        if name == "readkey" {
            emit("    bl __nifla_readkey")
            return
        }
        if bareOnlyTools[name] != nil || guestDeskTools[name] != nil || guestDoorTools[name] != nil {
            // The disk and guest tools: refused for this
            // target before translating; never emitted.
            emit("    b __halt_trap")
            return
        }
        let registers = ["x0", "x1", "x2", "x3", "x4", "x5"]
        var slotCount = 0
        for arg in args {
            emitExpr(arg)
            emit("    str x0, [sp, #-16]!")
            slotCount += 1
            if slots(for: kindOf(arg)) == 2 {
                emit("    str x1, [sp, #-16]!")
                slotCount += 1
            }
        }
        if slotCount > 0 {
            for index in stride(from: slotCount - 1, through: 0, by: -1) {
                emit("    ldr \(registers[index]), [sp], #16")
            }
        }
        emit("    bl __fn_\(name)")
    }
}

// MARK: - Building the ARM binary

// Runs a build tool; gives back its exit status and what it
// said on its error channel. (The ARM build's own copy of
// the x86 road's helper, which is private to its file.)
private func runLLVMTool(_ path: String, _ arguments: [String]) -> (status: Int32, words: String)? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    let errorPipe = Pipe()
    process.standardError = errorPipe
    process.standardOutput = Pipe()
    do {
        try process.run()
    } catch {
        return nil
    }
    process.waitUntilExit()
    let words = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return (process.terminationStatus, words)
}

// Finds an LLVM tool (clang, ld.lld) for the aarch64 build:
// the bench's own toolchain trees first (the Swift
// toolchains this workspace builds with carry clang and
// lld), then the usual system places, then the PATH.
private func findLLVMTool(_ name: String) -> String? {
    // The bench's home is the HOME the shell was given; the
    // account's own directory may differ when the build runs
    // under another name, so HOME is asked first.
    let home = ProcessInfo.processInfo.environment["HOME"]
        ?? FileManager.default.homeDirectoryForCurrentUser.path
    var candidates = [
        "\(home)/workspace/turtle-browser/harness-039/toolchain/swift-6.0.3-RELEASE-ubuntu24.04/usr/bin/\(name)",
        "\(home)/workspace/turtle-browser/harness-038/toolchain/swift-6.0.3-RELEASE-ubuntu24.04/usr/bin/\(name)",
        "\(home)/qemu-root/usr/bin/\(name)",
        "/usr/bin/\(name)",
        "/usr/local/bin/\(name)",
    ]
    if let path = ProcessInfo.processInfo.environment["PATH"] {
        for dir in path.split(separator: ":") {
            candidates.append("\(dir)/\(name)")
        }
    }
    for candidate in candidates {
        if FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
    }
    return nil
}

func compileBareARM(inputPath: String, output: String?, program: [Stmt], videoRequest: (width: Int, height: Int, depth: Int)? = nil, fail: (String, Int32) -> Int32) -> Int32 {
    if let video = videoRequest, video.depth != 32 {
        return fail("The ARM target's picture screen speaks 32-bit color (the virt machine's ramfb in its XRGB8888 form) — ask for a depth of 32, like: --video 1024x768x32. The depth you asked for was \(video.depth).", 2)
    }
    let validator = BareValidator(guestMode: false)
    do {
        try validator.validate(program)
    } catch let error as NiflaError {
        return fail(error.spoken, 1)
    } catch {
        return fail("Something went wrong while reading the program.", 1)
    }
    if let refusal = armRefusal(in: program) {
        return fail(refusal, 1)
    }

    var translator = BareTranslatorARM(validator: validator)
    translator.videoRequest = videoRequest
    let asm = translator.translate(program, sourceName: URL(fileURLWithPath: inputPath).lastPathComponent)

    let outputPath: String
    if let output {
        outputPath = output
    } else {
        outputPath = URL(fileURLWithPath: inputPath).deletingPathExtension().path + ".elf"
    }
    let asmPath = outputPath + ".s"
    do {
        try asm.write(toFile: asmPath, atomically: true, encoding: .utf8)
    } catch {
        return fail("I couldn't write the assembly to '\(asmPath)'.", 2)
    }

    guard let clang = findLLVMTool("clang") else {
        return fail("I couldn't find clang, which the ARM build uses to assemble the program (it must be able to target aarch64). Install an LLVM toolchain and try again.", 2)
    }
    guard let lld = findLLVMTool("ld.lld") else {
        return fail("I couldn't find the LLVM linker (ld.lld), which the ARM build uses to link the program. Install an LLVM toolchain and try again.", 2)
    }

    let scratch = FileManager.default.temporaryDirectory
        .appendingPathComponent("niflac-bare-arm-\(ProcessInfo.processInfo.processIdentifier)")
    do {
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    } catch {
        return fail("I couldn't set up a scratch folder to build in.", 2)
    }
    defer { try? FileManager.default.removeItem(at: scratch) }

    // The virt machine's memory starts at 0x40000000 and
    // the kernel is loaded at its start; the device tree
    // stands low in memory, well below, and is only read.
    let linkerScript = """
        ENTRY(_start)
        SECTIONS {
            . = 0x40000000;
            .text : { *(.text) }
            .rodata : { *(.rodata) }
            .data : { *(.data) }
            .bss : {
                __bss_start = .;
                *(.bss)
                *(COMMON)
                . = ALIGN(8);
                __bss_end = .;
            }
            . = ALIGN(4096);
            __kernel_end = .;
        }
        """
    let scriptPath = scratch.appendingPathComponent("bare-arm.ld").path
    let objectPath = scratch.appendingPathComponent("bare-arm.o").path
    do {
        try linkerScript.write(toFile: scriptPath, atomically: true, encoding: .utf8)
    } catch {
        return fail("I couldn't set up a scratch folder to build in.", 2)
    }

    guard let assembled = runLLVMTool(clang, ["-target", "aarch64-none-elf", "-c", asmPath, "-o", objectPath]) else {
        return fail("I couldn't start the assembler at '\(clang)'.", 2)
    }
    if assembled.status != 0 {
        return fail("The bare program in '\(inputPath)' couldn't be assembled for aarch64. What the assembler said:\n\(assembled.words)", 1)
    }
    guard let linked = runLLVMTool(lld, ["-T", scriptPath, objectPath, "-o", outputPath]) else {
        return fail("I couldn't start the linker at '\(lld)'.", 2)
    }
    if linked.status != 0 {
        return fail("The bare program in '\(inputPath)' couldn't be linked for aarch64. What the linker said:\n\(linked.words)", 1)
    }

    print("Made \(outputPath) — a bare-metal program for aarch64, compiled from \(inputPath). It boots on its own on an ARM machine (QEMU's virt): no operating system underneath, and it speaks over the serial line.")
    print("The assembly it was made from is kept at \(asmPath), if you'd like to read it.")
    return 0
}
