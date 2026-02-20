import { describe, it } from "node:test";
import * as assert from "node:assert/strict";
import {
  RpcError,
  PARSE_ERROR,
  METHOD_NOT_FOUND,
  INTERNAL_ERROR,
  SESSION_NOT_FOUND,
  SESSION_ALREADY_CLOSED,
  INVALID_PARAMS,
  TOOL_NOT_FOUND,
  TOOL_TIMEOUT,
  APPROVAL_NOT_FOUND,
  CONTEXT_NOT_FOUND,
} from "../src/errors/rpc-error";

describe("RpcError", () => {
  it("should be an instance of Error", () => {
    const err = new RpcError(-32000, "test error");
    assert.ok(err instanceof Error);
  });

  it("should be an instance of RpcError", () => {
    const err = new RpcError(-32000, "test error");
    assert.ok(err instanceof RpcError);
  });

  it("should have correct name", () => {
    const err = new RpcError(-32000, "test error");
    assert.equal(err.name, "RpcError");
  });

  it("should store code and message", () => {
    const err = new RpcError(SESSION_NOT_FOUND, "Session not found: abc-123");
    assert.equal(err.code, SESSION_NOT_FOUND);
    assert.equal(err.message, "Session not found: abc-123");
  });

  it("should store optional data field", () => {
    const data = { sessionId: "abc-123", extra: 42 };
    const err = new RpcError(SESSION_NOT_FOUND, "Not found", data);
    assert.deepEqual(err.data, data);
  });

  it("should have undefined data when not provided", () => {
    const err = new RpcError(-32000, "test error");
    assert.equal(err.data, undefined);
  });

  it("should produce correct stack trace", () => {
    const err = new RpcError(-32000, "test error");
    assert.ok(err.stack);
    assert.ok(err.stack.includes("RpcError"));
  });

  describe("toJsonRpcError()", () => {
    it("should return code and message without data", () => {
      const err = new RpcError(METHOD_NOT_FOUND, "Method not found: foo.bar");
      const jsonErr = err.toJsonRpcError();
      assert.deepEqual(jsonErr, {
        code: METHOD_NOT_FOUND,
        message: "Method not found: foo.bar",
      });
    });

    it("should include data field when present", () => {
      const data = { detail: "extra info" };
      const err = new RpcError(INTERNAL_ERROR, "Something broke", data);
      const jsonErr = err.toJsonRpcError();
      assert.deepEqual(jsonErr, {
        code: INTERNAL_ERROR,
        message: "Something broke",
        data: { detail: "extra info" },
      });
    });

    it("should include data even when data is null", () => {
      const err = new RpcError(-32000, "test", null);
      const jsonErr = err.toJsonRpcError();
      assert.deepEqual(jsonErr, {
        code: -32000,
        message: "test",
        data: null,
      });
    });

    it("should exclude data when data is undefined", () => {
      const err = new RpcError(-32000, "test");
      const jsonErr = err.toJsonRpcError();
      assert.ok(!("data" in jsonErr));
    });
  });

  describe("prototype chain", () => {
    it("should pass instanceof checks after Object.setPrototypeOf", () => {
      const err = new RpcError(-32000, "test");
      // Verify the prototype chain fix works
      assert.ok(err instanceof RpcError);
      assert.ok(err instanceof Error);
      assert.ok(Object.getPrototypeOf(err) === RpcError.prototype);
    });

    it("should be catchable as RpcError in try/catch", () => {
      let caught = false;
      try {
        throw new RpcError(SESSION_NOT_FOUND, "not found");
      } catch (e) {
        if (e instanceof RpcError) {
          caught = true;
          assert.equal(e.code, SESSION_NOT_FOUND);
        }
      }
      assert.ok(caught, "RpcError should be caught by instanceof check");
    });

    it("should be distinguishable from plain Error", () => {
      const rpcErr = new RpcError(-32000, "rpc");
      const plainErr = new Error("plain");
      assert.ok(rpcErr instanceof RpcError);
      assert.ok(!(plainErr instanceof RpcError));
    });
  });

  describe("error codes", () => {
    it("standard JSON-RPC codes should be negative", () => {
      assert.ok(PARSE_ERROR < 0);
      assert.ok(METHOD_NOT_FOUND < 0);
      assert.ok(INTERNAL_ERROR < 0);
      assert.ok(INVALID_PARAMS < 0);
    });

    it("Dochi-specific codes should be in -32xxx range", () => {
      const dochiCodes = [
        SESSION_NOT_FOUND,
        SESSION_ALREADY_CLOSED,
        TOOL_NOT_FOUND,
        TOOL_TIMEOUT,
        APPROVAL_NOT_FOUND,
        CONTEXT_NOT_FOUND,
      ];
      for (const code of dochiCodes) {
        assert.ok(code >= -32999 && code <= -32000, `Code ${code} should be in -32xxx range`);
      }
    });

    it("standard and Dochi codes should not overlap", () => {
      const standardCodes = [PARSE_ERROR, METHOD_NOT_FOUND, INTERNAL_ERROR, INVALID_PARAMS];
      const dochiCodes = [
        SESSION_NOT_FOUND,
        SESSION_ALREADY_CLOSED,
        TOOL_NOT_FOUND,
        TOOL_TIMEOUT,
        APPROVAL_NOT_FOUND,
        CONTEXT_NOT_FOUND,
      ];
      for (const sc of standardCodes) {
        for (const dc of dochiCodes) {
          assert.notEqual(sc, dc, `Standard code ${sc} overlaps with Dochi code ${dc}`);
        }
      }
    });
  });
});
