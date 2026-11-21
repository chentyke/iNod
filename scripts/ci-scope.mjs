// Read NUL-separated paths from the diff between the trial merge and its first parent.
import { readFileSync } from "node:fs";

const paths = readFileSync(0, "utf8").split("\0").filter(Boolean);
function isDocumentation(path) {
    return ["README.md", "CONTRIBUTING.md", "AGENTS.md", "LICENSE", ".github/PULL_REQUEST_TEMPLATE.md"].includes(path)
        || (path.startsWith("docs/") && path.endsWith(".md"))
        || (path.startsWith("docs/readme/") && path.endsWith(".png"))
        || (path.startsWith(".github/ISSUE_TEMPLATE/") && path.endsWith(".yml"));
}

const code = paths.filter(path => !isDocumentation(path));
console.log(`skip-swift=${paths.length > 0 && code.length === 0}`);
console.log(`skip-ui=${paths.length > 0 && code.every(path =>
    path.startsWith("Tests/NodeSeekCoreTests/") || path.startsWith("Tests/NodeSeekClientTests/")
)}`);
