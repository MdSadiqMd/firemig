import type { ArtifactKind } from "@firemig/common";
import type { FileSystemAdapter } from "../platform/adapters.js";
import type { ArtifactHttpClient } from "../artifacts/artifact-http.js";
import type { WorkerService } from "../worker/index.js";

export interface AgentServerOptions {
    worker: WorkerService;
    fs: FileSystemAdapter;
    authToken?: string;
    artifactHttp?: ArtifactHttpClient;
    logger?: boolean;
}

export interface IdParams {
    id: string;
}

export interface ArtifactParams extends IdParams {
    kind: ArtifactKind;
}

export interface MigrationParams extends IdParams {
    migrationId: string;
}
