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
    const opacity = afterColor.match(/^\.opacity\(([^()]*(?:\([^()]*\)[^()]*)*)\)/);
    if (!opacity) return 1;
    const values = (opacity[1].match(/\b\d*\.?\d+\b/g) ?? []).map(Number);
    return values.length > 0 ? Math.max(...values) : 1;
}

const rules = [
    {
        id: "gradient",
        doc: "颜色克制：不用渐变铺色",
        test: (line) => {
            if (!/\b(?:Linear|Radial|Angular|Elliptical)Gradient\s*\(|\.gradient\b/.test(line)) return false;
            // A fade made only of black, white and clear is a mask, not color.
            return new RegExp(String.raw`(?<!\w)${statusColor}`).test(line)
                || /Color\.(?!black\b|white\b|clear\b)\w+|\w+\.gradient\b/.test(line);
        },
    },
    {
        id: "tinted-fill",
        doc: "颜色克制：状态色的填充或背景不透明度低于 0.15",
        test: (line, previous) => {
            // Dots are small by nature; the rule is about tinted cards, rows and blocks.
            if (/\bCircle\(\)\s*\.fill\(/.test(line) || (/\bCircle\(\)\s*$/.test(previous) && /^\s*\.fill\(/.test(line))) return false;
            const fill = new RegExp(String.raw`\.(?:fill|background)\(\s*${statusColor}`, "g");
            return [...line.matchAll(fill)].some((match) => strongest(line.slice(match.index + match[0].length)) >= 0.15);
        },
    },
    {
        id: "tinted-stroke",
        doc: "颜色克制：卡片不用醒目的彩色描边（不透明度不超过 0.3）",
        test: (line) => {
            const stroke = new RegExp(String.raw`\bstrokeBorder\(\s*${statusColor}`, "g");
            return [...line.matchAll(stroke)].some((match) => strongest(line.slice(match.index + match[0].length)) > 0.3);
        },
    },
];

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
    lines.forEach((line, index) => {
        const code = line.replace(/\/\/.*$/, "");
        for (const rule of rules) {
            if (!rule.test(code, (lines[index - 1] ?? "").replace(/\/\/.*$/, ""))) continue;
            const exemption = (line.match(allow) ?? lines[index - 1]?.match(allow));
            if (exemption && exemption[1].trim().length > 0) continue;
            const note = exemption ? "（design-check: allow 后要写原因）" : "";
            problems.push(`${relative(root, file)}:${index + 1}: [${rule.id}] ${rule.doc}${note}\n    ${line.trim()}`);
        }
    });
}

if (problems.length > 0) {
    console.error(problems.join("\n"));
    console.error(`\n${problems.length} 处不符合 docs/DESIGN.md。确有必要时，在该行或上一行写 // design-check: allow <原因>。`);
    process.exit(1);
}
console.log("Design checks passed.");
