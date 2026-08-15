import * as http from "node:http";

export interface UnixHttpRequest {
    socketPath: string;
    method: "GET" | "PUT" | "PATCH";
    path: string;
    headers: Record<string, string>;
    body?: string;
    timeoutMs: number;
}

export interface UnixHttpResponse {
    statusCode: number;
    headers: http.IncomingHttpHeaders;
    body: string;
}

export type UnixHttpTransport = (request: UnixHttpRequest) => Promise<UnixHttpResponse>;

export const nodeUnixHttpTransport: UnixHttpTransport = (request) =>
    new Promise((resolve, reject) => {
        const call = http.request(
            {
                socketPath: request.socketPath,
                method: request.method,
                path: request.path,
                headers: request.headers,
                timeout: request.timeoutMs,
            },
            (response) => {
                const chunks: Buffer[] = [];
                response.on("data", (chunk: Buffer) => chunks.push(chunk));
                response.on("end", () =>
                    resolve({
                        statusCode: response.statusCode ?? 500,
                        headers: response.headers,
                        body: Buffer.concat(chunks).toString("utf8"),
                    }),
                );
            },
        );
        call.once("timeout", () =>
            call.destroy(new Error(`Firecracker API timed out after ${request.timeoutMs}ms`)),
        );
        call.once("error", reject);
        if (request.body !== undefined) call.write(request.body);
        call.end();
    });
