import githubTools from "@github-tools/eve-extension";

// Any mounted extension triggers the failing code path. This one is public on
// npm; the token is never used because the build doesn't call any tools.
export default githubTools({ token: "unused" });
