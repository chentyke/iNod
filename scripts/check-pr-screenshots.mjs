// Fails a pull request that changes the app's interface without screenshots in its description.
// Usage: PR_BODY=... node scripts/check-pr-screenshots.mjs <base-ref> [head-ref]
//
// Interface changes are edits to Swift files under NodeSeek/ beyond comments and blank lines. The "截图或录屏"
// section must embed at least one uploaded image or video; saying the screenshots were checked locally does not count.

import { execFileSync } from "node:child_process";

const [base, head = "HEAD"] = process.argv.slice(2);
if (!base) {
    console.error("Usage: PR_BODY=... node scripts/check-pr-screenshots.mjs <base-ref> [head-ref]");
    process.exit(2);
}

const git = (...args) => execFileSync("git", args, { encoding: "utf8" });

/// Whether a file's diff changes anything other than comments and blank lines.
function changesCode(path) {
    return git("diff", "-U0", `${base}...${head}`, "--", path)
        .split("\n")
        .filter((line) => /^[+-](?![+-]{2} )/.test(line))
        .some((line) => !/^[+-]\s*(?:\/\/.*)?$/.test(line));
}

const changed = git("diff", "--name-only", `${base}...${head}`)
    .split("\n")
    .filter((path) => path.startsWith("NodeSeek/") && path.endsWith(".swift"))
    .filter(changesCode);

if (changed.length === 0) {
    console.log("No interface files changed; screenshots are optional.");
    process.exit(0);
}

const body = (process.env.PR_BODY ?? "").replace(/<!--[\s\S]*?-->/g, "");
const parts = body.split(/^##\s*截图或录屏\s*$/m);
const section = parts[1]?.split(/^##\s/m)[0] ?? "";

const media = [
    /<img\s[^>]*src=["']?https?:\/\/[^\s"'>]+/i, // <img src="https://...">
    /!\[[^\]]*\]\(\s*https?:\/\/[^)\s]+/, // ![alt](https://...)
    /https:\/\/github\.com\/user-attachments\/assets\/[\w-]+/, // drag-and-drop uploads, including videos
    /<video\s[^>]*src=["']?https?:\/\//i,
];

const problems = [];
if (parts.length < 2) problems.push("PR 描述缺少“## 截图或录屏”一节。");
else if (!media.some((pattern) => pattern.test(section))) {
    problems.push("“截图或录屏”一节里没有上传的图片或视频。把截图直接拖进 PR 描述即可上传。");
}

if (problems.length > 0) {
    console.error(`这个 PR 改了 ${changed.length} 个界面文件，例如 ${changed.slice(0, 3).join("、")}。`);
    console.error(problems.join("\n"));
    console.error("改动前后的截图都要上传；只写“本地已确认”不算。见 CONTRIBUTING.md。");
    process.exit(1);
}
console.log(`Screenshots found for ${changed.length} changed interface files.`);
