import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import Home from "@/app/page";

describe("トップページ", () => {
  it("「todo-app」見出しを表示する", () => {
    render(<Home />);
    expect(
      screen.getByRole("heading", { name: "todo-app", level: 1 }),
    ).toBeInTheDocument();
  });
});
