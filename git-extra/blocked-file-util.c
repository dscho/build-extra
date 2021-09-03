#include <windows.h>
#include <tlhelp32.h>
#include <stdio.h>
#include <stdlib.h>

static int find_pids_blocking_files(WCHAR *top_level_directory, int len)
{
	int ret = 0;
	HANDLE process_snapshot;
	PROCESSENTRY32W process_entry;
	WCHAR *path;
	BOOL res;

	process_snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
	if (process_snapshot == INVALID_HANDLE_VALUE)
		return -1;

	process_entry.dwSize = sizeof(PROCESSENTRY32W);
	res = Process32FirstW(process_snapshot, &process_entry);

	while (res) {
		DWORD pid = process_entry.th32ProcessID;
		HANDLE module_snapshot;
		MODULEENTRY32W module_entry;

		if (pid <= 0)
			goto next_process;
		module_snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE |
							   TH32CS_SNAPMODULE32,
							   pid);
		if (module_snapshot == INVALID_HANDLE_VALUE)
			goto next_process;
		module_entry.dwSize = sizeof(MODULEENTRY32W);
		res = Module32FirstW(module_snapshot, &module_entry);
		while (res) {
			path = module_entry.szExePath;
			if (!_wcsnicmp(top_level_directory, path, len) &&
			    path[len] == L'\\') {
				ret++;
				fprintf(stderr, "Pid %ld uses %S\n", pid, path);
				break;
			}
			res = Module32NextW(module_snapshot, &module_entry);
		}
		CloseHandle(module_snapshot);
next_process:
		res = Process32NextW(process_snapshot, &process_entry);
	}

	CloseHandle(process_snapshot);

	return ret;
}

static int recycle(WCHAR *path)
{
	int len = wcslen(path), ret;
	WCHAR *list;
	SHFILEOPSTRUCTW opt;

	list = malloc((len + 2) * sizeof(WCHAR));
	if (!list)
		return -1;
	memcpy(list, path, len * sizeof(WCHAR));
	list[len] = list[len + 1] = L'\0';

	memset(&opt, 0, sizeof(SHFILEOPSTRUCTW));
	opt.pFrom = list;
	opt.hwnd = NULL;
	opt.wFunc = FO_DELETE;
	opt.fFlags = FOF_SILENT | FOF_NOERRORUI | FOF_ALLOWUNDO |
		FOF_NOCONFIRMMKDIR | FOF_NOCONFIRMATION;

	ret = SHFileOperationW(&opt);

	free(list);
	return ret;
}

int get_current_directory_of_pid(DWORD pid, WCHAR **directory, WCHAR **cmdline)
{
	HANDLE process = OpenProcess(PROCESS_ALL_ACCESS, FALSE, pid);
	struct {
		PVOID Reserved1;
		PVOID PebBaseAddress;
		PVOID Reserved2[2];
		ULONG_PTR UniqueProcessId;
		PVOID Reserved3;
	} info = { NULL };
	ULONG len;
	HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
	NTSTATUS (*NtQueryInformationProcess)(HANDLE ProcessHandle,
					      int ProcessInformationClass,
					      PVOID ProcessInformation,
					      ULONG ProcessInformationLength,
					      PULONG ReturnLength) =
		(NTSTATUS (*)(HANDLE, int, PVOID, ULONG, PULONG))
		(void (*)(void))
		GetProcAddress(ntdll, "NtQueryInformationProcess");
	BOOL isWow;
	size_t peb_offset = 0;
	size_t parameters_offset, cwd_offset, cmdline_offset;
	size_t pointer_size, bytes_read;
	char *address = NULL, *string_address = NULL;
	USHORT string_length;

	if (!process || !NtQueryInformationProcess ||
	    NtQueryInformationProcess(process, 0, &info, sizeof(info), &len)) {
fail_cwd:
		if (process)
			CloseHandle(process);
		return -1;
	}

	if (IsWow64Process(process, &isWow) && isWow) {
		peb_offset = 0x1000;
		parameters_offset = 0x10;
		cwd_offset = 0x24;
		cmdline_offset = 0x40;
		pointer_size = 4;
	} else {
		parameters_offset = 0x20;
		cwd_offset = 0x38;
		cmdline_offset = 0x70;
		pointer_size = 8;
	}

printf("peb: %p\n", info.PebBaseAddress + peb_offset);
	if (!ReadProcessMemory(process, info.PebBaseAddress + peb_offset + parameters_offset,
			       &address, pointer_size, &bytes_read) ||
	    bytes_read != pointer_size)
		goto fail_cwd;

printf("upp: %p\n", address);
	if (!ReadProcessMemory(process, address + cwd_offset,
			       &string_length, sizeof(USHORT), &bytes_read) ||
	    bytes_read != sizeof(USHORT))
		goto fail_cwd;

printf("len: %u\n", (unsigned)string_length);
	if (!ReadProcessMemory(process, address + cwd_offset + pointer_size,
			       &string_address, pointer_size, &bytes_read) ||
	    bytes_read != pointer_size)
		goto fail_cwd;

printf("string @%p\n", string_address);
	*directory = malloc((string_length + 1) * sizeof(wchar_t));
	if (!ReadProcessMemory(process, string_address, *directory,
			       string_length * sizeof(wchar_t), &bytes_read) ||
	    bytes_read != string_length * sizeof(wchar_t))
		goto fail_cwd;
	(*directory)[string_length] = L'\0';

printf("string: '%ls'\n", *directory);
	if (!ReadProcessMemory(process, address + cmdline_offset,
			       &string_length, sizeof(USHORT), &bytes_read) ||
	    bytes_read != sizeof(USHORT))
		goto fail_cwd;

printf("len: %u\n", (unsigned)string_length);
	if (!ReadProcessMemory(process, address + cmdline_offset + pointer_size,
			       &string_address, pointer_size, &bytes_read) ||
	    bytes_read != pointer_size)
		goto fail_cwd;

printf("string @%p\n", string_address);
	*cmdline = malloc((string_length + 1) * sizeof(wchar_t));
	if (!ReadProcessMemory(process, string_address, *cmdline,
			       string_length * sizeof(wchar_t), &bytes_read) ||
	    bytes_read != string_length * sizeof(wchar_t))
		goto fail_cwd;
	(*cmdline)[string_length] = L'\0';

printf("cmdline: '%ls'\n", *cmdline);
	CloseHandle(process);
	return 0;
}

int WINAPI WinMain(HINSTANCE instance, HINSTANCE prev, LPSTR command_line,
		int show)
{
	int wargc, ret;
	WCHAR **wargv = CommandLineToArgvW(GetCommandLineW(), &wargc);

	if (wargc == 3 && !wcscmp(L"blocking-pids", wargv[1])) {
		int len;

		for (len = 0; wargv[2][len]; len++)
			if (wargv[2][len] == L'/')
				wargv[2][len] = L'\\';

		if (len && wargv[2][len - 1] == L'\\')
			len--;

		ret = !!find_pids_blocking_files(wargv[2], len);
	} else if (wargc == 3 && !wcscmp(L"recycle", wargv[1])) {
		ret = recycle(wargv[2]);
	} else if (wargc == 3 && !wcscmp(L"cwd", wargv[1])) {
		WCHAR *directory, *cmdline;
		ret = !!get_current_directory_of_pid(wcstoul(wargv[2], NULL, 10), &directory, &cmdline);
	} else {
		fprintf(stderr,
			"Usage: %S <command> [<arguments>...]\n"
			"Commands:\n"
			"\tblocking-pids <top-level-directory>\n"
			"\trecycle <path>\n",
			wargv[0]);
		ret = 1;
	}

	LocalFree(wargv);
	return ret;
}
