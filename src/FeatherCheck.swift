// FeatherCheck — the doorman's test anyone can run (Stone 21).
//
// A third face of the one program this repo builds (see
// main.swift): called by the name `feathercheck`, it reads a
// .feather file and answers in plain words whether its card
// is true — the name, what it needs, the byte count and
// checksum the card states, the byte count and checksum the
// program as it stands reckons to, and a clear verdict line.
//
// The card is read as the compiler lays it (Stone 20): a
// first line "CARDNULL FEATHER 1", then name:, needs:,
// bytes: and checksum: lines, then a blank line, then the
// program bytes. (The OS's door needs only the bytes: and
// checksum: lines to do its work and steps over the rest;
// the checker reads the whole card, as it was laid.)
//
// Every answer is printed to standard output, verdict lines
// and refusals alike, so the answer can be read by a person
// or compared by a proof. The exit code carries the verdict
// too: 0 when the card is true, 1 when it is not — a damaged
// card, or a program that does not match its card — and 2
// when the tool itself was called wrongly.

import Foundation

func featherCheckMain(arguments: [String]) -> Int32 {
    guard arguments.count == 2 else {
        FileHandle.standardError.write(Data("Usage: feathercheck <file.feather>\n".utf8))
        return 2
    }
    let path = arguments[1]

    func damaged(_ reason: String) -> Int32 {
        print("This is not a whole feather: \(reason)")
        return 1
    }

    let bytes: [UInt8]
    do {
        bytes = [UInt8](try Data(contentsOf: URL(fileURLWithPath: path)))
    } catch {
        return damaged("the file '\(path)' could not be read.")
    }

    // Walk the card's lines: each ends at a newline byte
    // (10); the card ends at a blank line, and the program
    // is every byte after it.
    func lineBounds(from start: Int) -> (end: Int, next: Int)? {
        var i = start
        while i < bytes.count {
            if bytes[i] == 10 { return (i, i + 1) }
            i += 1
        }
        return nil
    }
    func lineText(_ from: Int, _ to: Int) -> String {
        String(decoding: bytes[from..<to], as: UTF8.self)
    }

    guard let first = lineBounds(from: 0) else {
        return damaged("the card never ends — its blank line never comes, so where the program begins cannot be told.")
    }
    guard lineText(0, first.end) == "CARDNULL FEATHER 1" else {
        return damaged("the card's first line is not CARDNULL FEATHER 1 — this file does not carry a feather's card.")
    }

    var name: String? = nil
    var needs: String? = nil
    var statedBytes: Int? = nil
    var statedSumText: String? = nil
    var statedSum: UInt64? = nil
    var programStart: Int? = nil

    var p = first.next
    while p < bytes.count {
        if bytes[p] == 10 {
            programStart = p + 1
            break
        }
        guard let lb = lineBounds(from: p) else {
            return damaged("the card never ends — its blank line never comes, so where the program begins cannot be told.")
        }
        let line = lineText(p, lb.end)
        if line.hasPrefix("name: ") {
            name = String(line.dropFirst(6))
        } else if line.hasPrefix("needs: ") {
            needs = String(line.dropFirst(7))
        } else if line.hasPrefix("bytes: ") {
            let tail = line.dropFirst(7)
            guard !tail.isEmpty, tail.allSatisfy({ $0 >= "0" && $0 <= "9" }), let n = Int(tail) else {
                return damaged("the card's 'bytes:' line does not carry a whole number.")
            }
            statedBytes = n
        } else if line.hasPrefix("checksum: ") {
            let tail = String(line.dropFirst(10))
            let hexDigits = Set("0123456789abcdefABCDEF")
            guard tail.count == 16, tail.allSatisfy({ hexDigits.contains($0) }), let v = UInt64(tail, radix: 16) else {
                return damaged("the card's 'checksum:' line is not sixteen hex letters.")
            }
            statedSumText = tail
            statedSum = v
        }
        // Any other line is stepped over, as the format allows.
        p = lb.next
    }

    guard let start = programStart else {
        return damaged("the card never ends — its blank line never comes, so where the program begins cannot be told.")
    }
    guard let theName = name else {
        return damaged("the card has no 'name:' line.")
    }
    guard let theNeeds = needs else {
        return damaged("the card has no 'needs:' line.")
    }
    guard let theStatedBytes = statedBytes else {
        return damaged("the card has no 'bytes:' line, so the program's length cannot be checked.")
    }
    guard let theStatedSum = statedSum, let theStatedSumText = statedSumText else {
        return damaged("the card has no 'checksum:' line, so the program's wholeness cannot be checked.")
    }

    let program = Array(bytes[start...])
    let reckoned = fnv1a64(program)
    let reckonedText = String(format: "%016llx", reckoned)

    print("Feather: \(theName)")
    print("Needs: \(theNeeds)")
    print("The card says the program is \(theStatedBytes) bytes, with checksum \(theStatedSumText).")
    print("The program as it stands is \(program.count) bytes, with checksum \(reckonedText).")
    if program.count == theStatedBytes && reckoned == theStatedSum {
        print("The card is true: the program is whole, and a door may let this feather in.")
        return 0
    }
    print("The card is not true: the program does not match its card, so a door must refuse this feather.")
    return 1
}
