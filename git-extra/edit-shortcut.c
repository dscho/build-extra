#include <stdio.h>
#include <shlobj.h>

static void die(const char *message)
{
	CoUninitialize();
	fprintf(stderr, "%s\n", message);
	fprintf(stderr, "last error: %d\n", GetLastError());
	exit(1);
}

static void maybe_initialize_console_props(NT_CONSOLE_PROPS **props,
	IShellLinkDataList *psldl)
{
	HRESULT hres;

	if (*props)
		return;

	hres = psldl->lpVtbl->CopyDataBlock(psldl, NT_CONSOLE_PROPS_SIG,
					    (void **)props);
	if (SUCCEEDED(hres))
		return;

	/*
	 * The shortcut file contains no such block; initialize one according
	 * to https://blogs.msdn.microsoft.com/oldnewthing/20130527-00/?p=4253/
	 */
	*props = LocalAlloc(LMEM_FIXED, sizeof(**props));
	ZeroMemory(*props, sizeof(**props));
	(*props)->cbSize = sizeof(**props);
	(*props)->dwSignature = NT_CONSOLE_PROPS_SIG;
	(*props)->wFillAttribute = FOREGROUND_BLUE | FOREGROUND_GREEN |
		FOREGROUND_RED; // white on black
	(*props)->wPopupFillAttribute = BACKGROUND_BLUE | BACKGROUND_GREEN |
		BACKGROUND_RED | BACKGROUND_INTENSITY |
		FOREGROUND_BLUE | FOREGROUND_RED;
	// purple on white
	(*props)->dwWindowSize.X = 132; // 132 columns wide
	(*props)->dwWindowSize.Y = 50; // 50 lines tall
	(*props)->dwScreenBufferSize.X = 132; // 132 columns wide
	(*props)->dwScreenBufferSize.Y = 1000; // large scrollback
	(*props)->uCursorSize = 25; // small cursor
	(*props)->bQuickEdit = TRUE; // turn QuickEdit on
	(*props)->bAutoPosition = TRUE;
	(*props)->uHistoryBufferSize = 25;
	(*props)->uNumberOfHistoryBuffers = 4;
	(*props)->ColorTable[ 0] = RGB(0x00, 0x00, 0x00);
	(*props)->ColorTable[ 1] = RGB(0x00, 0x00, 0x80);
	(*props)->ColorTable[ 2] = RGB(0x00, 0x80, 0x00);
	(*props)->ColorTable[ 3] = RGB(0x00, 0x80, 0x80);
	(*props)->ColorTable[ 4] = RGB(0x80, 0x00, 0x00);
	(*props)->ColorTable[ 5] = RGB(0x80, 0x00, 0x80);
	(*props)->ColorTable[ 6] = RGB(0x80, 0x80, 0x00);
	(*props)->ColorTable[ 7] = RGB(0xC0, 0xC0, 0xC0);
	(*props)->ColorTable[ 8] = RGB(0x80, 0x80, 0x80);
	(*props)->ColorTable[ 9] = RGB(0x00, 0x00, 0xFF);
	(*props)->ColorTable[10] = RGB(0x00, 0xFF, 0x00);
	(*props)->ColorTable[11] = RGB(0x00, 0xFF, 0xFF);
	(*props)->ColorTable[12] = RGB(0xFF, 0x00, 0x00);
	(*props)->ColorTable[13] = RGB(0xFF, 0x00, 0xFF);
	(*props)->ColorTable[14] = RGB(0xFF, 0xFF, 0x00);
	(*props)->ColorTable[15] = RGB(0xFF, 0xFF, 0xFF);
}

int main(int argc, char **argv)
{
	const char *progname = argv[0], *shortcut_path;
	const char *work_dir = NULL, *arguments = NULL, *icon_file = NULL;
	const char *description = NULL, *path = NULL;
	int show_cmd = 1, quick_edit = -1, history_buffer_size = 0;
	int number_of_history_buffers = 0;
	NT_CONSOLE_PROPS *console_props = NULL;
	WCHAR wsz[1024];
	HRESULT hres;
	IShellLink *psl;
	IShellLinkDataList *psldl;
	IPersistFile *ppf;

	while (argc > 2) {
		if (argv[1][0] != '-')
			break;
		if (!strcmp(argv[1], "--work-dir"))
			work_dir = argv[2];
		else if (!strcmp(argv[1], "--path"))
			path = argv[2];
		else if (!strcmp(argv[1], "--arguments"))
			arguments = argv[2];
		else if (!strcmp(argv[1], "--show-cmd"))
			show_cmd = atoi(argv[2]);
		else if (!strcmp(argv[1], "--icon-file"))
			icon_file = argv[2];
		else if (!strcmp(argv[1], "--description"))
			description = argv[2];
		else if (!strcmp(argv[1], "--quick-edit"))
			quick_edit = atoi(argv[2]);
		else if (!strcmp(argv[1], "--history-buffer-size"))
			history_buffer_size = atoi(argv[2]);
		else if (!strcmp(argv[1], "--number-of-history-buffers"))
			number_of_history_buffers = atoi(argv[2]);
		else {
			fprintf(stderr, "Unknown option: %s\n", argv[1]);
			return 1;
		}

		argc -= 2;
		argv += 2;
	}

	if (argc > 1 && !strcmp(argv[1], "--")) {
		argc--;
		argv++;
	}

	if (argc != 2) {
		fprintf(stderr, "Usage: %s [options] <shortcut>\n",
			progname);
		return 1;
	}

	shortcut_path = argv[1];
	wsz[0] = 0;
	MultiByteToWideChar(CP_ACP, 0, shortcut_path, -1, wsz, 1024);

	hres = CoInitialize(NULL);
	if (FAILED(hres))
		die ("Could not initialize OLE");

	hres = CoCreateInstance(&CLSID_ShellLink, NULL, CLSCTX_INPROC_SERVER,
			&IID_IShellLink, (void **)&psl);

	if (FAILED(hres))
		die ("Could not get ShellLink interface");

	hres = psl->lpVtbl->QueryInterface(psl, &IID_IPersistFile,
			(void **) &ppf);
	if (FAILED(hres))
		die ("Could not get PersistFile interface");

	hres = psl->lpVtbl->QueryInterface(psl, &IID_IShellLinkDataList,
			(void **) &psldl);
	if (FAILED(hres))
		die ("Could not get PersistFile interface");

	hres = ppf->lpVtbl->Load(ppf, (const WCHAR *)wsz, STGM_READWRITE);
	if (FAILED(hres))
		die ("Could not load link");

	if (path) {
		hres = psl->lpVtbl->SetPath(psl, path);
		if (FAILED(hres))
			die ("Could not set path");
	}

	if (work_dir)
		psl->lpVtbl->SetWorkingDirectory(psl, work_dir);

	if (show_cmd)
		psl->lpVtbl->SetShowCmd(psl, show_cmd);

	if (icon_file)
		psl->lpVtbl->SetIconLocation(psl, icon_file, 0);
	if (arguments)
		psl->lpVtbl->SetArguments(psl, arguments);
	if (description)
		psl->lpVtbl->SetDescription(psl, description);

	if (quick_edit >= 0) {
		maybe_initialize_console_props(&console_props, psldl);
		console_props->bQuickEdit = quick_edit ? TRUE : FALSE;
	}
	if (history_buffer_size) {
		maybe_initialize_console_props(&console_props, psldl);
		console_props->uHistoryBufferSize = history_buffer_size;
	}
	if (number_of_history_buffers) {
		maybe_initialize_console_props(&console_props, psldl);
		console_props->uNumberOfHistoryBuffers = number_of_history_buffers;
	}

	if (console_props) {
		hres = psldl->lpVtbl->RemoveDataBlock(psldl,
						      NT_CONSOLE_PROPS_SIG);
		hres = psldl->lpVtbl->AddDataBlock(psldl, console_props);
		if (FAILED(hres))
			die("Could not add data block");
		LocalFree(console_props);
	}

	hres = ppf->lpVtbl->Save(ppf, NULL, TRUE);
	if (SUCCEEDED(hres))
		hres = ppf->lpVtbl->SaveCompleted(ppf, wsz);

	ppf->lpVtbl->Release(ppf);
	psl->lpVtbl->Release(psl);
	psldl->lpVtbl->Release(psldl);

	if (FAILED(hres))
		die ("Could not save link");

	CoUninitialize();
	return 0;
}
