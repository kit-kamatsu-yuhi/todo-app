import { describe, it, expect, beforeAll, beforeEach, afterAll } from "vitest";
import { testPrisma, setupTestDb, cleanDb } from "./helpers/db";

beforeAll(async () => {
  await setupTestDb();
});

beforeEach(async () => {
  await cleanDb();
});

afterAll(async () => {
  await testPrisma.$disconnect();
});

describe("User / Todo スキーマ統合テスト", () => {
  describe("ST1: User 作成", () => {
    it("User を作成すると id・email・createdAt が返る", async () => {
      const user = await testPrisma.user.create({
        data: {
          email: "test@example.com",
          passwordHash: "hashed_password",
        },
      });

      // cuid は先頭が 'c' で始まる
      expect(user.id).toMatch(/^c/);
      expect(user.email).toBe("test@example.com");
      expect(user.createdAt).toBeInstanceOf(Date);
    });
  });

  describe("ST2: email unique 制約", () => {
    it("同一 email で 2 回 User 作成すると P2002 エラーが発生する", async () => {
      await testPrisma.user.create({
        data: {
          email: "duplicate@example.com",
          passwordHash: "hashed_password",
        },
      });

      await expect(
        testPrisma.user.create({
          data: {
            email: "duplicate@example.com",
            passwordHash: "hashed_password",
          },
        }),
      ).rejects.toThrow(
        expect.objectContaining({
          code: "P2002",
        }),
      );
    });
  });

  describe("ST3: Todo completed デフォルト値", () => {
    it("completed を指定せずに Todo を作成すると completed が false になる", async () => {
      const user = await testPrisma.user.create({
        data: {
          email: "todo-default@example.com",
          passwordHash: "hashed_password",
        },
      });

      const todo = await testPrisma.todo.create({
        data: {
          userId: user.id,
          title: "タスク",
          position: 1,
        },
      });

      expect(todo.completed).toBe(false);
    });
  });

  describe("ST4: FK 制約（存在しない userId）", () => {
    it("存在しない userId で Todo 作成すると P2003 エラーが発生する", async () => {
      await expect(
        testPrisma.todo.create({
          data: {
            userId: "non-existent-id",
            title: "test",
            position: 1,
          },
        }),
      ).rejects.toMatchObject({ code: "P2003" });
    });
  });

  describe("ST5: Cascade 削除", () => {
    it("User を削除すると紐づく Todo も削除される", async () => {
      const user = await testPrisma.user.create({
        data: {
          email: "cascade@example.com",
          passwordHash: "hashed_password",
        },
      });

      await testPrisma.todo.create({
        data: {
          userId: user.id,
          title: "削除されるタスク",
          position: 1,
        },
      });

      // User 削除前に Todo が存在することを確認
      const todosBefore = await testPrisma.todo.findMany({
        where: { userId: user.id },
      });
      expect(todosBefore).toHaveLength(1);

      await testPrisma.user.delete({ where: { id: user.id } });

      // User 削除後に Todo も消えていること
      const todosAfter = await testPrisma.todo.findMany({
        where: { userId: user.id },
      });
      expect(todosAfter).toHaveLength(0);
    });
  });
});
