// Checks the app's SwiftUI code against the rules in docs/DESIGN.md that can be read from source.
// Usage: node scripts/check-design.mjs [directory]   (defaults to NodeSeek/)
//
// A line that breaks a rule on purpose carries `// design-check: allow <reason>` on the same line
// or the line above. The reason is required.

import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";

const root = new URL("..", import.meta.url).pathname;
const target = join(root, process.argv[2] ?? "NodeSeek");

// Colors that carry meaning (status, emphasis). Neutral ink, card, tray and hairline colors are fine anywhere.
const statusColor = String.raw`(?:Color\.)?\.?(?:seekGreen|red|orange|blue|green|purple|yellow|pink|mint|teal|indigo|cyan|brown|accentColor|tint)\b`;

/// The highest opacity a color could take, read from the `.opacity(...)` right after it.
/// Without one the color is drawn at full strength; `.opacity(isOn ? 0.8 : 0.3)` counts as 0.8.
function strongest(afterColor) {
    const opacity = afterColor.match(/^\s*\.opacity\s*\(([^()]*(?:\([^()]*\)[^()]*)*)\)/);
    if (!opacity) return 1;
    const values = (opacity[1].match(/\b\d*\.?\d+\b/g) ?? []).map(Number);
    return values.length > 0 ? Math.max(...values) : 1;
}

const gradients = /\b(?:Linear|Radial|Angular|Elliptical)Gradient\s*\(|\.gradient\b/;
const gradientColor = new RegExp(String.raw`(?<!\w)${statusColor}`);
function usesColorGradient(line) {
    // A fade made only of black, white and clear is a mask, not color.
    return gradients.test(line) && (gradientColor.test(line)
        || /Color\.(?!black\b|white\b|clear\b)\w+|\w+\.gradient\b/.test(line));
}

// Scan direct color arguments across line breaks, including simple trailing closures.
// Code review still covers colors computed elsewhere or supplied through variables.
const fills = new RegExp(String.raw`\.(?:fill\s*\(|background\s*[(\{])\s*${statusColor}`, "g");
const strokes = new RegExp(String.raw`\.(?:stroke|strokeBorder)\s*\(\s*${statusColor}`, "g");

const allow = /\/\/\s*design-check:\s*allow\b(.*)$/;

function swiftFiles(directory) {
    return readdirSync(directory).flatMap((name) => {
        const path = join(directory, name);
        if (statSync(path).isDirectory()) return swiftFiles(path);
        return name.endsWith(".swift") ? [path] : [];
    });
}

const problems = [];
for (const file of swiftFiles(target)) {
    const lines = readFileSync(file, "utf8").split("\n");
    const codeLines = lines.map(line => line.replace(/\/\/.*$/, ""));
    const code = codeLines.join("\n");
    const report = (index, id, rule) => {
        const line = lines[index];
        const exemption = line.match(allow) ?? lines[index - 1]?.match(allow);
        if (exemption?.[1].trim()) return;
        const note = exemption ? "（design-check: allow 后要写原因）" : "";
        problems.push(`${relative(root, file)}:${index + 1}: [${id}] ${rule}${note}\n    ${line.trim()}`);
    };
    codeLines.forEach((line, index) => {
        if (usesColorGradient(line)) report(index, "gradient", "颜色克制：不用渐变铺色");
    });
    for (const match of code.matchAll(fills)) {
        const before = code.slice(0, match.index);
        // Dots are small by nature; the rule is about tinted cards, rows and blocks.
        if (match[0].startsWith(".fill") && /\bCircle\(\)\s*$/.test(before)) continue;
        if (strongest(code.slice(match.index + match[0].length)) >= 0.15) {
            report(before.split("\n").length - 1, "tinted-fill", "颜色克制：状态色的填充或背景不透明度低于 0.15");
        }
    }
    for (const match of code.matchAll(strokes)) {
        if (strongest(code.slice(match.index + match[0].length)) > 0.3) {
            report(code.slice(0, match.index).split("\n").length - 1, "tinted-stroke",
                "颜色克制：卡片不用醒目的彩色描边（不透明度不超过 0.3）");
        }
    }
}

if (problems.length > 0) {
    console.error(problems.join("\n"));
    console.error(`\n${problems.length} 处不符合 docs/DESIGN.md。确有必要时，在该行或上一行写 // design-check: allow <原因>。`);
    process.exit(1);
}
console.log("Design checks passed.");
