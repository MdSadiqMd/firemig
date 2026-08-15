import { spawn } from "node:child_process";
import * as fs from "node:fs";
import * as fsp from "node:fs/promises";
import * as os from "node:os";
import type { Readable, Writable } from "node:stream";

export interface SyncFile {
    writeFile(data: string | Uint8Array): Promise<void>;
    sync(): Promise<void>;
    close(): Promise<void>;
}

export interface FileSystemAdapter {
    mkdir(
        path: string,
        options?: { recursive?: boolean; mode?: number },
    ): Promise<string | undefined>;
    readFile(path: string, encoding: "utf8"): Promise<string>;
    open(path: string, flags: string, mode?: number): Promise<SyncFile>;
    rename(from: string, to: string): Promise<void>;
    link(existingPath: string, newPath: string): Promise<void>;
    rm(path: string, options?: { recursive?: boolean; force?: boolean }): Promise<void>;
    stat(path: string): Promise<{ size: number; isFile(): boolean }>;
    copyFile(from: string, to: string): Promise<void>;
    chmod(path: string, mode: number): Promise<void>;
    createReadStream(path: string, options?: { start?: number; end?: number }): Readable;
    createWriteStream(path: string, options?: { flags?: string }): Writable;
    watch(
        path: string,
        options: { signal: AbortSignal },
    ): AsyncIterable<{ eventType: string; filename: string | null }>;
}

export interface SpawnedProcess {
    pid: number;
    exited: Promise<{ code: number | null; signal: NodeJS.Signals | null }>;
    kill(signal?: NodeJS.Signals): boolean;
}

export interface ProcessAdapter {
    spawn(
        file: string,
        args: readonly string[],
        options?: { cwd?: string; env?: NodeJS.ProcessEnv },
    ): SpawnedProcess;
    run(
        file: string,
        args: readonly string[],
        options?: { cwd?: string; env?: NodeJS.ProcessEnv },
    ): Promise<{ stdout: string; stderr: string }>;
}

export interface OsAdapter {
    hostname(): string;
    platform(): NodeJS.Platform;
    arch(): string;
    release(): string;
}

export const nodeFileSystem: FileSystemAdapter = {
    mkdir: (path, options) => fsp.mkdir(path, options),
    readFile: (path, encoding) => fsp.readFile(path, encoding),
    open: (path, flags, mode) => fsp.open(path, flags, mode),
    rename: (from, to) => fsp.rename(from, to),
    link: (existingPath, newPath) => fsp.link(existingPath, newPath),
    rm: (path, options) => fsp.rm(path, options),
    stat: async (path) => fsp.stat(path),
    copyFile: (from, to) => fsp.copyFile(from, to),
    chmod: (path, mode) => fsp.chmod(path, mode),
    createReadStream: (path, options) => fs.createReadStream(path, options),
    createWriteStream: (path, options) => fs.createWriteStream(path, options),
    watch: (path, options) => fsp.watch(path, { ...options, encoding: "utf8" }),
};

function processResult(child: ReturnType<typeof spawn>): SpawnedProcess {
    const exited = new Promise<{ code: number | null; signal: NodeJS.Signals | null }>(
        (resolve, reject) => {
            child.once("error", reject);
            child.once("exit", (code, signal) => resolve({ code, signal }));
        },
    );
    if (child.pid === undefined) throw new Error("Spawned process did not receive a PID");
    return { pid: child.pid, exited, kill: (signal) => child.kill(signal) };
}

export const nodeProcessAdapter: ProcessAdapter = {
    spawn(file, args, options) {
        return processResult(
            spawn(file, [...args], {
                stdio: "inherit",
                ...(options?.cwd === undefined ? {} : { cwd: options.cwd }),
                ...(options?.env === undefined ? {} : { env: options.env }),
            }),
        );
    },
    run(file, args, options) {
        return new Promise((resolve, reject) => {
            const child = spawn(file, [...args], {
                stdio: ["ignore", "pipe", "pipe"],
                ...(options?.cwd === undefined ? {} : { cwd: options.cwd }),
                ...(options?.env === undefined ? {} : { env: options.env }),
            });
            const stdout: Buffer[] = [];
            const stderr: Buffer[] = [];
            child.stdout.on("data", (chunk: Buffer) => stdout.push(chunk));
            child.stderr.on("data", (chunk: Buffer) => stderr.push(chunk));
            child.once("error", reject);
            child.once("close", (code, signal) => {
                const result = {
                    stdout: Buffer.concat(stdout).toString(),
                    stderr: Buffer.concat(stderr).toString(),
                };
                if (code === 0) resolve(result);
                else
                    reject(
                        new Error(`${file} exited with ${code ?? signal}: ${result.stderr.trim()}`),
                    );
            });
        });
    },
};

export const nodeOsAdapter: OsAdapter = {
    hostname: os.hostname,
    platform: os.platform,
    arch: os.arch,
    release: os.release,
};
