import { defineTool } from "eve/tools";
import { z } from "zod";

export default defineTool({
  description: "Echo the input back.",
  inputSchema: z.object({ text: z.string() }),
  async execute({ text }) {
    return { text };
  },
});
