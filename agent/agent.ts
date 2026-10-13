import { defineAgent } from "eve";

// The build never calls the model; any model id works.
export default defineAgent({
  model: "anthropic/claude-sonnet-5-5",
  modelContextWindowTokens: 200_000,
});
