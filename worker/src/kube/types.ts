/** The slice of a Kubernetes Pod this worker reads. */
export interface PodContainer {
  name: string;
  image?: string;
  resources?: { requests?: Record<string, string>; limits?: Record<string, string> };
}

export interface PodContainerStatus {
  name: string;
  image?: string;
  ready?: boolean;
  restartCount?: number;
  state?: Record<string, unknown>;
  lastState?: Record<string, unknown>;
}

export interface Pod {
  metadata: { name: string; uid: string; namespace: string; labels?: Record<string, string>; creationTimestamp?: string };
  spec?: { nodeName?: string; containers?: PodContainer[] };
  status?: { phase?: string; podIP?: string; containerStatuses?: PodContainerStatus[] };
}

export interface PodList {
  items: Pod[];
}
