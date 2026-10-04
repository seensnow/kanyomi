type FileSystemPermissionMode = 'read' | 'readwrite'
type FileSystemPermissionState = 'denied' | 'granted' | 'prompt'

type PermissionCapableHandle = FileSystemHandle & {
  queryPermission?: (options?: {
    mode?: FileSystemPermissionMode
  }) => Promise<FileSystemPermissionState>
  requestPermission?: (options?: {
    mode?: FileSystemPermissionMode
  }) => Promise<FileSystemPermissionState>
}

type DirectoryPickerWindow = Window & {
  showDirectoryPicker?: (options?: {
    id?: string
    mode?: FileSystemPermissionMode
    startIn?: 'desktop' | 'documents' | 'downloads' | 'music' | 'pictures' | 'videos'
  }) => Promise<FileSystemDirectoryHandle>
}

export const supportsDirectoryPicker =
  typeof (window as DirectoryPickerWindow).showDirectoryPicker === 'function'

export async function pickDirectory() {
  const showDirectoryPicker = (window as DirectoryPickerWindow).showDirectoryPicker

  if (!showDirectoryPicker) {
    throw new Error('Directory picker is not supported.')
  }

  return showDirectoryPicker.call(window, {
    id: 'simple-reader-library',
    mode: 'read',
  })
}

export async function requestReadPermission(handle: FileSystemHandle) {
  const permissionHandle = handle as PermissionCapableHandle
  const options = { mode: 'read' as const }

  if (await permissionHandle.queryPermission?.(options) === 'granted') {
    return true
  }

  if (!permissionHandle.requestPermission) {
    return true
  }

  return await permissionHandle.requestPermission(options) === 'granted'
}
