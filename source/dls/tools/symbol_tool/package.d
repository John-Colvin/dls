/*
 *Copyright (C) 2018 Laurent Tréguier
 *
 *This file is part of DLS.
 *
 *DLS is free software: you can redistribute it and/or modify
 *it under the terms of the GNU General Public License as published by
 *the Free Software Foundation, either version 3 of the License, or
 *(at your option) any later version.
 *
 *DLS is distributed in the hope that it will be useful,
 *but WITHOUT ANY WARRANTY; without even the implied warranty of
 *MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *GNU General Public License for more details.
 *
 *You should have received a copy of the GNU General Public License
 *along with DLS.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

module dls.tools.symbol_tool;

import dls.protocol.interfaces : CompletionItemKind, SymbolKind, SymbolInformation;
import dls.tools.tool : Tool;
import dls.util.uri : Uri;
import dsymbol.symbol : CompletionKind;
import std.container : RedBlackTree;

int compareLocations(inout(SymbolInformation) s1, inout(SymbolInformation) s2)
{
    //dfmt off
    return s1.location.uri < s2.location.uri ? -1
        : s1.location.uri > s2.location.uri ? 1
        : s1.location.range.start.line < s2.location.range.start.line ? -1
        : s1.location.range.start.line > s2.location.range.start.line ? 1
        : s1.location.range.start.character < s2.location.range.start.character ? -1
        : s1.location.range.start.character > s2.location.range.start.character ? 1
        : 0;
    //dfmt on
}

alias SymbolInformationTree = RedBlackTree!(SymbolInformation, compareLocations, true);

private string[string] macros;
private immutable CompletionItemKind[CompletionKind] completionKinds;
private immutable SymbolKind[CompletionKind] symbolKinds;

private enum ProjectType : int
{
    dub,
    custom
}

shared static this()
{
    import dub.internal.vibecompat.core.log : LogLevel, setLogLevel;

    setLogLevel(LogLevel.none);
}

static this()
{
    //dfmt off
    macros = [
        "_"             : "",
        "B"             : "**$0**",
        "I"             : "_$0_",
        "U"             : "$0",
        "P"             : "\n\n$0",
        "DL"            : "$0",
        "DT"            : "$0",
        "DD"            : "$0",
        "TABLE"         : "$0",
        "TR"            : "$0",
        "TH"            : "$0",
        "TD"            : "$0",
        "OL"            : "\n\n$0",
        "UL"            : "\n\n$0",
        "LI"            : "- $0",
        "BIG"           : "$0",
        "SMALL"         : "$0",
        "BR"            : "\n\n$0",
        "LINK"          : "[$0]($0)",
        "LINK2"         : "[$1]($+)",
        "RED"           : "$0",
        "BLUE"          : "$0",
        "GREEN"         : "$0",
        "YELLOW"        : "$0",
        "BLACK"         : "$0",
        "WHITE"         : "$0",
        "D_CODE"        : "$0",
        "D_INLINE_CODE" : "$0",
        "LF"            : "\n",
        "LPAREN"        : "(",
        "RPAREN"        : ")",
        "BACKTICK"      : "`",
        "DOLLAR"        : "$",
        "DDOC"          : "$0",
        "BIGOH"         : "O($0)",
        "D"             : "$0",
        "D_COMMENT"     : "$0",
        "D_STRING"      : "\"$0\"",
        "D_KEYWORD"     : "$0",
        "D_PSYMBOL"     : "$0",
        "D_PARAM"       : "$0",
        "LREF"          : "$0",
        "REF"           : "$0",
        "REF1"          : "$0",
        "MREF"          : "$0",
        "MREF1"         : "$0"
    ];

    completionKinds = [
        CompletionKind.className            : CompletionItemKind.class_,
        CompletionKind.interfaceName        : CompletionItemKind.interface_,
        CompletionKind.structName           : CompletionItemKind.struct_,
        CompletionKind.unionName            : CompletionItemKind.interface_,
        CompletionKind.variableName         : CompletionItemKind.variable,
        CompletionKind.memberVariableName   : CompletionItemKind.field,
        CompletionKind.keyword              : CompletionItemKind.keyword,
        CompletionKind.functionName         : CompletionItemKind.function_,
        CompletionKind.enumName             : CompletionItemKind.enum_,
        CompletionKind.enumMember           : CompletionItemKind.enumMember,
        CompletionKind.packageName          : CompletionItemKind.folder,
        CompletionKind.moduleName           : CompletionItemKind.module_,
        CompletionKind.aliasName            : CompletionItemKind.variable,
        CompletionKind.templateName         : CompletionItemKind.function_,
        CompletionKind.mixinTemplateName    : CompletionItemKind.function_
    ];

    symbolKinds = [
        CompletionKind.className            : SymbolKind.class_,
        CompletionKind.interfaceName        : SymbolKind.interface_,
        CompletionKind.structName           : SymbolKind.struct_,
        CompletionKind.unionName            : SymbolKind.interface_,
        CompletionKind.variableName         : SymbolKind.variable,
        CompletionKind.memberVariableName   : SymbolKind.field,
        CompletionKind.keyword              : SymbolKind.constant,
        CompletionKind.functionName         : SymbolKind.function_,
        CompletionKind.enumName             : SymbolKind.enum_,
        CompletionKind.enumMember           : SymbolKind.enumMember,
        CompletionKind.packageName          : SymbolKind.package_,
        CompletionKind.moduleName           : SymbolKind.module_,
        CompletionKind.aliasName            : SymbolKind.variable,
        CompletionKind.templateName         : SymbolKind.function_,
        CompletionKind.mixinTemplateName    : SymbolKind.function_
    ];
    //dfmt on
}

class SymbolTool : Tool
{
    import dcd.common.messages : AutocompleteRequest, RequestKind;
    import dls.protocol.definitions : Location, MarkupContent, Position, Range, WorkspaceEdit;
    import dls.protocol.interfaces : CompletionItem, DocumentHighlight, DocumentSymbol, Hover;
    import dsymbol.modulecache : ASTAllocator, ModuleCache;
    import dub.dub : Dub;

    private static SymbolTool _instance;

    static void initialize()
    {
        import std.algorithm : filter;
        import std.array : array;
        import std.file : exists;

        _instance = new SymbolTool();
        _instance.importDirectories(defaultImportPaths.filter!exists.array);
        addConfigHook(_instance.toString(), {
            _instance.importDirectories(_configuration.symbol.importPaths);
        });
    }

    static void shutdown()
    {
        removeConfigHook(_instance.toString());
        destroy(_instance);
    }

    @property static SymbolTool instance()
    {
        return _instance;
    }

    version (Windows)
    {
        @property private static string[] _compilerConfigPaths()
        {
            import std.algorithm : splitter;
            import std.file : exists;
            import std.path : buildNormalizedPath;
            import std.process : environment;

            foreach (path; splitter(environment["PATH"], ';'))
            {
                if (exists(buildNormalizedPath(path, "dmd.exe")))
                {
                    return [buildNormalizedPath(path, "sc.ini")];
                }
            }

            return [];
        }
    }
    else version (Posix)
    {
        //dfmt off
        private static immutable _compilerConfigPaths = [
            "/Library/D/dmd/bin/dmd.conf",
            "/etc/dmd.conf",
            "/usr/local/etc/dmd.conf",
            "/usr/local/bin/dmd.conf",
            "/etc/ldc2.conf",
            "/usr/local/etc/ldc2.conf",
            "/home/linuxbrew/.linuxbrew/etc/dmd.conf"
        ];
        //dfmt on
    }
    else
    {
        private static immutable string[] _compilerConfigPaths;
    }

    private ProjectType[string] _workspaceProjectTypes;
    private string[string][string] _workspaceDependencies;
    private string[][string] _workspaceDependenciesPaths;
    private ASTAllocator _allocator;
    private ModuleCache _cache;

    @property Uri[] workspacesFilesUris()
    {
        import dls.util.document : Document;
        import std.algorithm : canFind, filter, map, reduce;
        import std.array : array;
        import std.file : SpanMode, dirEntries, isFile;
        import std.path : globMatch;

        bool isImported(const Uri uri)
        {
            import std.algorithm : startsWith;

            foreach (path; _cache.getImportPaths())
            {
                if (uri.path.startsWith(Uri.fromPath(path).path))
                {
                    return true;
                }
            }

            return false;
        }

        return reduce!q{a ~ b}(Document.uris.array,
                _workspaceDependencies.byKey.map!(w => dirEntries(w, SpanMode.depth).map!q{a.name}
                    .filter!(file => globMatch(file, "*.{d,di}"))
                    .filter!(file => !Document.uris.map!q{a.path}.canFind(file))
                    .filter!isFile
                    .map!(Uri.fromPath)
                    .filter!isImported
                    .array));
    }

    @property ref ModuleCache cache()
    {
        return _cache;
    }

    @property private static string[] defaultImportPaths()
    {
        import std.algorithm : each, sort, uniq;
        import std.array : array, replace;
        import std.conv : to;
        import std.file : FileException, exists, readText;
        import std.path : asNormalizedPath, dirName;
        import std.regex : matchAll;

        string[] paths;

        foreach (confPath; _compilerConfigPaths)
        {
            if (!exists(confPath))
            {
                continue;
            }

            try
            {
                readText(confPath).matchAll(`-I[^\s"]+`)
                    .each!(m => paths ~= m.hit[2 .. $].replace("%@P%",
                            dirName(confPath)).asNormalizedPath().to!string);
                break;
            }
            catch (FileException e)
            {
                // File could't be read
            }
        }

        if (paths.length > 0)
        {
            return paths.sort().uniq().array;
        }

        version (linux)
        {
            import std.algorithm : map;
            import std.path : buildPath;

            foreach (path; ["/snap", "/var/lib/snapd/snap"])
            {
                const dmdSnapPath = buildPath(path, "dmd");
                const ldcSnapIncludePath = buildPath(path, "ldc2", "current", "include", "d");

                if (exists(dmdSnapPath))
                {
                    return ["druntime", "phobos"].map!(end => buildPath(dmdSnapPath,
                            "current", "import", end)).array;
                }
                else if (exists(ldcSnapIncludePath))
                {
                    return [ldcSnapIncludePath];
                }
            }
        }

        paths = homeDlangImportPaths;
        return paths.length > 0 ? paths : customLdcImportPaths;
    }

    @property private static string[] homeDlangImportPaths()
    {
        import std.algorithm : filter, map, sort;
        import std.array : array;
        import std.file : SpanMode, dirEntries, exists, isDir;
        import std.path : buildPath;
        import std.process : environment;

        version (Posix)
        {
            static bool less(const string a, const string b)
            {
                import dub.semver : compareVersions;
                import std.algorithm : findSplit;
                import std.path : baseName;

                return compareVersions(findSplit(baseName(a), "-")[2],
                        findSplit(baseName(b), "-")[2]) == 1;
            }

            const dlangPath = buildPath(environment["HOME"], "dlang");

            if (!exists(dlangPath))
            {
                return [];
            }

            auto dmds = dirEntries(dlangPath, "dmd-*.*.*", SpanMode.shallow).map!(
                    entry => entry.name)
                .filter!isDir
                .array
                .sort!less;

            if (!dmds.empty)
            {
                return [buildPath(dmds.front, "src", "druntime", "src"),
                    buildPath(dmds.front, "src", "phobos")];
            }

            auto ldcs = dirEntries(dlangPath, "ldc-*.*.*", SpanMode.shallow).map!(
                    entry => entry.name)
                .filter!isDir
                .array
                .sort!less;

            if (!ldcs.empty)
            {
                return [buildPath(ldcs.front, "import")];
            }
        }

        return [];
    }

    @property private static string[] customLdcImportPaths()
    {
        import std.algorithm : each, sort, splitter, uniq;
        import std.file : exists;
        import std.path : buildPath, dirName;
        import std.process : environment;

        version (Windows)
        {
            const pathSep = ';';
            const ldc = "ldc2.exe";
        }
        else version (Posix)
        {
            const pathSep = ':';
            const ldc = "ldc2";
        }
        else
        {
            static assert(false, "Platform not suported");
        }

        foreach (path; splitter(environment["PATH"], pathSep))
        {
            if (exists(buildPath(path, ldc)))
            {
                return [buildPath(dirName(path), "import")];
            }
        }

        return [];
    }

    this()
    {
        _allocator = new ASTAllocator();
        _cache = ModuleCache(_allocator);
    }

    Uri getWorkspace(const Uri uri)
    {
        import std.algorithm : startsWith;
        import std.array : array;
        import std.path : buildNormalizedPath, pathSplitter;

        string[] workspacePathParts;

        foreach (path; _workspaceDependencies.byKey)
        {
            auto splitter = pathSplitter(path);

            if (pathSplitter(uri.path).startsWith(splitter))
            {
                auto pathParts = splitter.array;

                if (pathParts.length > workspacePathParts.length)
                {
                    workspacePathParts = pathParts;
                }
            }
        }

        return workspacePathParts.length > 0
            ? Uri.fromPath(buildNormalizedPath(workspacePathParts)) : null;
    }

    void importPath(const Uri uri)
    {
        import std.algorithm : any;
        import std.file : exists;
        import std.path : buildNormalizedPath;

        if (["dub.json", "dub.sdl"].any!(f => buildNormalizedPath(uri.path, f).exists()))
        {
            importDubProject(uri);
        }
        else
        {
            importCustomProject(uri);
        }
    }

    void importDubProject(const Uri uri)
    {
        import dls.protocol.messages.window : Util;
        import dls.util.constants : Tr;
        import dls.util.logger : logger;
        import dub.platform : BuildPlatform;
        import std.algorithm : map;
        import std.array : appender, array;
        import std.path : baseName, buildNormalizedPath;

        if (!validateProjectType(uri, ProjectType.dub))
        {
            return;
        }

        logger.infof("Importing dub project: %s", uri.path);

        auto d = getDub(uri);
        string[string] workspaceDeps;
        const buildSettingsList = d.project.rootPackage.recipe.buildSettings
            ~ d.project.rootPackage.recipe.configurations.map!q{a.buildSettings}.array;

        foreach (buildSettings; buildSettingsList)
        {
            foreach (depName, depVersion; buildSettings.dependencies)
            {
                workspaceDeps[depName] = depVersion.toString();
            }
        }

        if (uri.path in _workspaceDependencies && _workspaceDependencies[uri.path] != workspaceDeps)
        {
            auto id = Util.sendMessageRequest(Tr.app_upgradeSelections,
                    [Tr.app_upgradeSelections_upgrade], [d.projectName]);
            Util.bindMessageToRequestId(id, Tr.app_upgradeSelections, uri);
        }

        _workspaceDependencies[uri.path] = workspaceDeps;
        auto packages = appender([d.project.rootPackage]);

        foreach (sub; d.project.rootPackage.subPackages)
        {
            auto p = d.project.packageManager.getSubPackage(d.project.rootPackage,
                    baseName(sub.path), true);

            if (p !is null)
            {
                packages ~= p;
            }
        }

        foreach (p; packages.data)
        {
            const desc = p.describe(BuildPlatform.any, null, null);
            importDirectories(desc.importPaths.length > 0
                    ? desc.importPaths.map!(path => buildNormalizedPath(p.path.toString(),
                        path)).array : [uri.path]);
            importDubSelections(Uri.fromPath(desc.path));
        }
    }

    void importCustomProject(const Uri uri)
    {
        import dls.protocol.jsonrpc : InvalidParamsException;
        import dls.util.logger : logger;
        import std.algorithm : find, map;
        import std.array : array;
        import std.file : exists;
        import std.path : buildNormalizedPath;

        if (!validateProjectType(uri, ProjectType.custom))
        {
            return;
        }

        logger.infof("Importing custom project: %s", uri.path);

        auto possibleSourceDirs = ["source", "src", ""].map!(d => buildNormalizedPath(uri.path, d))
            .find!exists;

        if (possibleSourceDirs.empty)
        {
            throw new InvalidParamsException("invalid uri: " ~ uri);
        }

        string[string] deps;
        _workspaceDependencies[uri.path] = deps;
        importDirectories([possibleSourceDirs.front]);
        importGitSubmodules(uri);
    }

    void importDubSelections(const Uri uri)
    {
        import dls.util.logger : logger;
        import dls.util.uri : normalized;
        import std.algorithm : map, reduce;
        import std.array : array;
        import std.path : buildNormalizedPath;

        if (!validateProjectType(uri, ProjectType.dub))
        {
            return;
        }

        logger.infof("Importing dub selections for project: %s", uri.path);

        const d = getDub(uri);
        string[] newDependenciesPaths;

        foreach (dep; d.project.dependencies)
        {
            auto sourcePaths = reduce!q{a ~ b}(cast(string[])[],
                    dep.recipe.buildSettings.sourcePaths.values);
            auto pathsToImport = sourcePaths.map!(path => buildNormalizedPath(dep.path.toString(),
                    path).normalized).array;
            newDependenciesPaths ~= pathsToImport;
        }

        importDirectories(newDependenciesPaths);
        clearUnusedDirectories(uri, newDependenciesPaths);
    }

    void importGitSubmodules(const Uri uri)
    {
        import dls.util.logger : logger;
        import std.algorithm : findSplit;
        import std.file : exists;
        import std.path : buildPath;
        import std.stdio : File;
        import std.string : strip;

        if (!validateProjectType(uri, ProjectType.custom))
        {
            return;
        }

        const gitModulesPath = buildPath(uri.path, ".gitmodules");

        if (!exists(gitModulesPath))
        {
            return;
        }

        logger.infof("Importing git submodules for project: %s", uri.path);

        string[string] newWorkspaceDeps;
        string[] newDependenciesPaths;

        foreach (line; File(gitModulesPath, "r").byLineCopy)
        {
            auto parts = findSplit(line, "=");

            switch (strip(parts[0]))
            {
            case "path":
                const fullModUri = Uri.fromPath(buildPath(uri.path, strip(parts[2])));
                importCustomProject(fullModUri);
                newDependenciesPaths ~= fullModUri.path;
                break;

            case "url":
                newWorkspaceDeps[strip(parts[2])] = "";
                break;

            default:
                continue;
            }
        }

        clearUnusedDirectories(uri, newDependenciesPaths);
    }

    void clearPath(const Uri uri)
    {
        _workspaceProjectTypes.remove(uri.path);
        _workspaceDependencies.remove(uri.path);
        _workspaceDependenciesPaths.remove(uri.path);
        clearDirectories([uri.path]);
    }

    void upgradeSelections(const Uri uri)
    {
        import dls.util.logger : logger;
        import std.concurrency : spawn;
        import std.path : dirName;

        logger.infof("Upgrading dependencies from %s", dirName(uri.path));

        spawn((string uriString) {
            import dls.protocol.interfaces.dls : TranslationParams;
            import dls.protocol.jsonrpc : send;
            import dls.protocol.messages.methods : Dls;
            import dls.protocol.messages.window : Util;
            import dls.util.constants : Tr;
            import dub.dub : UpgradeOptions;

            send(Dls.UpgradeSelections.didStart,
                new TranslationParams(Tr.app_upgradeSelections_upgrading));

            try
            {
                getDub(new Uri(uriString)).upgrade(UpgradeOptions.upgrade | UpgradeOptions.select);
            }
            catch (Exception e)
            {
                Util.sendMessage(Tr.app_upgradeSelections_error, [e.msg]);
            }
            finally
            {
                send(Dls.UpgradeSelections.didStop);
            }
        }, uri.toString());
    }

    SymbolInformation[] symbol(const string query)
    {
        import dls.util.document : Document;
        import dls.util.logger : logger;
        import dsymbol.string_interning : internString;
        import dsymbol.symbol : DSymbol;
        import std.algorithm : any, canFind, map, startsWith;
        import std.array : appender, array;
        import std.file : SpanMode, dirEntries;
        import std.uni : toUpper;

        logger.infof(`Fetching symbols from workspace with query "%s"`, query);

        auto result = new SymbolInformationTree();
        const upperQuery = toUpper(query);

        void collectSymbolInformations(Uri symbolUri, const(DSymbol)* symbol,
                string containerName = "")
        {
            import std.typecons : nullable;

            if (symbol.symbolFile != symbolUri.path)
            {
                return;
            }

            auto name = symbol.name == "*constructor*" ? "this" : symbol.name;

            if (toUpper(name).canFind(upperQuery))
            {
                auto location = new Location(symbolUri, Document.get(symbolUri)
                        .wordRangeAtByte(symbol.location));
                result.insert(new SymbolInformation(name,
                        symbolKinds[symbol.kind], location, containerName.nullable));
            }

            foreach (s; symbol.getPartsByName(internString(null)))
            {
                collectSymbolInformations(symbolUri, s, name);
            }
        }

        foreach (moduleUri; workspacesFilesUris)
        {
            if (Document.uris.map!q{a.path}.canFind(moduleUri.path))
            {
                result.insert(symbol!SymbolInformation(moduleUri, query));
                continue;
            }

            auto moduleSymbol = _cache.cacheModule(moduleUri.path);

            if (moduleSymbol !is null)
            {
                foreach (symbol; moduleSymbol.getPartsByName(internString(null)))
                {
                    collectSymbolInformations(moduleUri, symbol);
                }
            }
        }

        return result.array;
    }

    SymbolType[] symbol(SymbolType)(Uri uri, const string query) // TODO: make uri const
    if (is(SymbolType == SymbolInformation) || is(SymbolType == DocumentSymbol))
    {
        import dls.tools.symbol_tool.internal.symbol_visitor : SymbolVisitor;
        import dls.util.document : Document;
        import dls.util.logger : logger;
        import dparse.lexer : LexerConfig, StringBehavior, StringCache, getTokensForParser;
        import dparse.parser : parseModule;
        import dparse.rollback_allocator : RollbackAllocator;
        import std.functional : toDelegate;

        if (query is null)
        {
            logger.infof("Fetching symbols from %s", uri.path);
        }

        static void doNothing(string, size_t, size_t, string, bool)
        {
        }

        auto stringCache = StringCache(StringCache.defaultBucketCount);
        auto tokens = getTokensForParser(Document.get(uri).toString(),
                LexerConfig(uri.path, StringBehavior.compiler), &stringCache);
        RollbackAllocator ra;
        const mod = parseModule(tokens, uri.path, &ra, toDelegate(&doNothing));
        auto visitor = new SymbolVisitor!SymbolType(uri, query);
        visitor.visit(mod);
        return visitor.result.data;
    }

    CompletionItem[] completion(const Uri uri, const Position position)
    {
        import dcd.common.messages : AutocompleteResponse, CompletionType;
        import dcd.server.autocomplete : complete;
        import dls.util.logger : logger;
        import std.algorithm : chunkBy, map, sort, uniq;
        import std.array : array;
        import std.conv : to;
        import std.json : JSONValue;

        logger.infof("Fetching completions for %s at position %s,%s", uri.path,
                position.line, position.character);

        auto request = getPreparedRequest(uri, position, RequestKind.autocomplete);
        static bool compareCompletionsLess(const AutocompleteResponse.Completion a,
                const AutocompleteResponse.Completion b)
        {
            //dfmt off
            return a.identifier < b.identifier ? true
                : a.identifier > b.identifier ? false
                : a.symbolFilePath < b.symbolFilePath ? true
                : a.symbolFilePath > b.symbolFilePath ? false
                : a.symbolLocation < b.symbolLocation;
            //dfmt on
        }

        static bool compareCompletionsEqual(const AutocompleteResponse.Completion a,
                const AutocompleteResponse.Completion b)
        {
            return a.symbolFilePath.length > 0 && a.symbolFilePath == b.symbolFilePath
                && a.symbolLocation == b.symbolLocation;
        }

        auto result = complete(request, _cache);

        if (result.completionType != CompletionType.identifiers)
        {
            return [];
        }

        return result.completions
            .sort!compareCompletionsLess
            .uniq!compareCompletionsEqual
            .chunkBy!q{a.identifier == b.identifier}
            .map!((resultGroup) {
                import std.array : appender;
                import std.uni : toLower;

                auto firstResult = resultGroup.front;
                auto item = new CompletionItem(firstResult.identifier);
                item.kind = completionKinds[firstResult.kind.to!CompletionKind];
                item.detail = firstResult.definition;

                auto data = appender!(string[][]);

                foreach (res; resultGroup)
                {
                    if (res.documentation.length > 0 && res.documentation.toLower() != "ditto")
                    {
                        data ~= [res.definition, res.documentation];
                    }
                }

                if (data.data.length > 0)
                {
                    item.data = JSONValue(data.data);
                }

                return item;
            })
            .array;
    }

    CompletionItem completionResolve(CompletionItem item)
    {
        import std.algorithm : map;
        import std.array : array;

        if (!item.data.isNull)
        {
            item.documentation = getDocumentation(
                    item.data.array.map!q{ [a[0].str, a[1].str] }.array);
            item.data.nullify();
        }

        return item;
    }

    Hover hover(const Uri uri, const Position position)
    {
        import dcd.server.autocomplete : getDoc;
        import dls.util.logger : logger;
        import std.algorithm : filter, map, sort, uniq;
        import std.array : array;

        logger.infof("Fetching documentation for %s at position %s,%s",
                uri.path, position.line, position.character);

        auto request = getPreparedRequest(uri, position, RequestKind.doc);
        auto result = getDoc(request, _cache);
        auto completions = result.completions
            .map!q{a.documentation}
            .filter!q{a.length > 0}
            .array
            .sort().uniq();

        return completions.empty ? null
            : new Hover(getDocumentation(completions.map!q{ ["", a] }.array));
    }

    Location[] definition(const Uri uri, const Position position)
    {
        import dcd.common.messages : CompletionType;
        import dcd.server.autocomplete.util : getSymbolsForCompletion;
        import dls.util.document : Document;
        import dls.util.logger : logger;
        import dparse.lexer : StringCache;
        import dparse.rollback_allocator : RollbackAllocator;
        import std.algorithm : filter;
        import std.array : appender;

        logger.infof("Finding declarations for %s at position %s,%s", uri.path,
                position.line, position.character);

        auto request = getPreparedRequest(uri, position, RequestKind.symbolLocation);
        auto stringCache = StringCache(StringCache.defaultBucketCount);
        RollbackAllocator ra;
        auto currentFileStuff = getSymbolsForCompletion(request,
                CompletionType.location, _allocator, &ra, stringCache, _cache);

        scope (exit)
        {
            currentFileStuff.destroy();
        }

        auto result = appender!(Location[]);

        foreach (symbol; currentFileStuff.symbols.filter!q{a.location > 0})
        {
            auto symbolUri = symbol.symbolFile == "stdin" ? uri : Uri.fromPath(symbol.symbolFile);
            auto document = Document.get(symbolUri);
            request.fileName = symbolUri.path;
            request.sourceCode = cast(ubyte[]) document.toString();
            request.cursorPosition = symbol.location + 1;
            auto stuff = getSymbolsForCompletion(request,
                    CompletionType.location, _allocator, &ra, stringCache, _cache);

            scope (exit)
            {
                stuff.destroy();
            }

            foreach (s; stuff.symbols)
            {
                result ~= new Location(symbolUri, document.wordRangeAtByte(s.location));
            }
        }

        return result.data;
    }

    Location[] typeDefinition(const Uri uri, const Position position)
    {
        import dcd.common.messages : CompletionType;
        import dcd.server.autocomplete.util : getSymbolsForCompletion;
        import dls.util.document : Document;
        import dls.util.logger : logger;
        import dparse.lexer : StringCache;
        import dparse.rollback_allocator : RollbackAllocator;
        import std.algorithm : filter, map, uniq;
        import std.array : appender;

        logger.infof("Finding type declaration for %s at position %s,%s",
                uri.path, position.line, position.character);

        auto request = getPreparedRequest(uri, position, RequestKind.symbolLocation);
        auto stringCache = StringCache(StringCache.defaultBucketCount);
        RollbackAllocator ra;
        auto stuff = getSymbolsForCompletion(request, CompletionType.location,
                _allocator, &ra, stringCache, _cache);

        scope (exit)
        {
            stuff.destroy();
        }

        auto result = appender!(Location[]);

        foreach (type; stuff.symbols
                .map!q{a.type}
                .filter!q{a !is null && a.location > 0 && a.symbolFile.length > 0}
                .uniq!q{a.symbolFile == b.symbolFile && a.location == b.location})
        {
            auto symbolUri = type.symbolFile == "stdin" ? uri : Uri.fromPath(type.symbolFile);
            result ~= new Location(symbolUri, Document.get(symbolUri)
                    .wordRangeAtByte(type.location));
        }

        return result.data;
    }

    Location[] references(const Uri uri, const Position position, bool includeDeclaration)
    {
        import dls.util.logger : logger;

        logger.infof("Finding references for %s at position %s,%s", uri.path,
                position.line, position.character);
        return referencesForFiles(uri, position, workspacesFilesUris, includeDeclaration);
    }

    DocumentHighlight[] highlight(const Uri uri, const Position position)
    {
        import dls.protocol.interfaces : DocumentHighlightKind;
        import dls.util.logger : logger;
        import std.algorithm : any;
        import std.array : appender;
        import std.path : filenameCmp;
        import std.typecons : nullable;

        logger.infof("Highlighting usages for %s at position %s,%s", uri.path,
                position.line, position.character);

        auto sources = referencesForFiles(uri, position, null, true);
        auto locations = referencesForFiles(uri, position, [uri], true);
        auto result = appender!(DocumentHighlight[]);

        foreach (location; locations)
        {
            auto kind = sources.any!(sourceLoc => location.range.start.line == sourceLoc.range.start.line
                    && location.range.start.character == sourceLoc.range.start.character
                    && filenameCmp(new Uri(location.uri).path, new Uri(sourceLoc.uri).path) == 0) ? DocumentHighlightKind
                .write : DocumentHighlightKind.read;
            result ~= new DocumentHighlight(location.range, kind.nullable);
        }

        return result.data;
    }

    WorkspaceEdit rename(const Uri uri, const Position position, const string newName)
    {
        import dls.protocol.definitions : TextDocumentEdit, TextEdit,
            VersionedTextDocumentIdentifier;
        import dls.protocol.state : initState;
        import dls.util.document : Document;
        import dls.util.logger : logger;
        import std.array : appender;
        import std.typecons : nullable;

        if ((initState.capabilities.textDocument.isNull || initState.capabilities.textDocument.rename.isNull
                || initState.capabilities.textDocument.rename.prepareSupport.isNull
                || !initState.capabilities.textDocument.rename.prepareSupport)
                && prepareRename(uri, position) is null)
        {
            return null;
        }

        logger.infof("Renaming symbol for %s at position %s,%s", uri.path,
                position.line, position.character);

        auto refs = references(uri, position, true);

        if (refs.length == 0)
        {
            return null;
        }

        TextEdit[][string] changes;
        auto documentChanges = appender!(TextDocumentEdit[]);

        foreach (reference; refs)
        {
            changes[reference.uri] ~= new TextEdit(reference.range, newName);
        }

        foreach (documentUri, textEdits; changes)
        {
            auto identifier = new VersionedTextDocumentIdentifier(documentUri,
                    Document.get(new Uri(documentUri)).version_);
            documentChanges ~= new TextDocumentEdit(identifier, textEdits);
        }

        return new WorkspaceEdit(changes.nullable, documentChanges.data.nullable);
    }

    Range prepareRename(const Uri uri, const Position position)
    {
        import dls.util.document : Document;
        import dls.util.logger : logger;
        import std.algorithm : any;

        logger.infof("Preparing symbol rename for %s at position %s,%s",
                uri.path, position.line, position.character);

        auto defs = definition(uri, position);
        return defs.length == 0
            || defs.any!(d => getWorkspace(new Uri(d.uri)) is null) ? null
            : Document.get(uri).wordRangeAtPosition(position);
    }

    private bool validateProjectType(const Uri uri, ProjectType type)
    {
        if (uri.path !in _workspaceProjectTypes)
        {
            _workspaceProjectTypes[uri.path] = type;
        }
        else if (_workspaceProjectTypes[uri.path] != type)
        {
            return false;
        }

        return true;
    }

    private void importDirectories(const string[] paths)
    {
        import dls.util.logger : logger;
        import dls.util.uri : normalized;
        import std.algorithm : map;
        import std.array : array;

        logger.infof("Importing directories: %s", paths);
        _cache.addImportPaths(paths.map!normalized.array);
    }

    private void clearDirectories(const string[] paths)
    {
        import dls.util.logger : logger;
        import dls.util.uri : normalized;
        import std.algorithm : map, startsWith;

        logger.infof("Clearing import directories: %s", paths);

        string[] pathsToRemove;

        foreach (path; paths.map!normalized)
        {
            foreach (importPath; _cache.getImportPaths())
            {
                if (importPath.startsWith(path))
                {
                    pathsToRemove ~= importPath;
                }
            }
        }

        _cache.removeImportPaths(pathsToRemove);
    }

    private void clearUnusedDirectories(const Uri uri, ref string[] newDependenciesPaths)
    {
        import std.algorithm : canFind, reduce;

        string[] pathsToRemove;
        const dependenciesPaths = uri.path in _workspaceDependenciesPaths
            ? _workspaceDependenciesPaths[uri.path] : [];

        _workspaceDependenciesPaths[uri.path] = newDependenciesPaths;
        const allDependenciesPaths = reduce!q{a ~ b}(cast(string[])[],
                _workspaceDependenciesPaths.byValue);

        foreach (path; dependenciesPaths)
        {
            if (!allDependenciesPaths.canFind(path))
            {
                pathsToRemove ~= path;
            }
        }

        clearDirectories(pathsToRemove);
    }

    private Location[] referencesForFiles(const Uri uri, const Position position,
            const Uri[] files, bool includeDeclaration)
    {
        import dcd.common.messages : CompletionType;
        import dcd.server.autocomplete.util : getSymbolsForCompletion;
        import dls.util.document : Document;
        import dparse.lexer : LexerConfig, StringBehavior, StringCache, Token,
            WhitespaceBehavior, getTokensForParser, tok;
        import dparse.rollback_allocator : RollbackAllocator;
        import dsymbol.string_interning : internString;
        import std.algorithm : filter;
        import std.array : appender;
        import std.range : zip;

        auto request = getPreparedRequest(uri, position, RequestKind.symbolLocation);
        auto stringCache = StringCache(StringCache.defaultBucketCount);
        auto sourceTokens = getTokensForParser(Document.get(uri).toString(),
                LexerConfig(uri.path, StringBehavior.compiler, WhitespaceBehavior.skip),
                &stringCache);
        RollbackAllocator ra;
        auto stuff = getSymbolsForCompletion(request, CompletionType.location,
                _allocator, &ra, stringCache, _cache);

        scope (exit)
        {
            stuff.destroy();
        }

        const(Token)* sourceToken;

        foreach (i, token; sourceTokens)
        {
            if (token.type == tok!"identifier" && request.cursorPosition >= token.index
                    && request.cursorPosition < token.index + token.text.length)
            {
                sourceToken = &sourceTokens[i];
                break;
            }
        }

        if (sourceToken is null)
        {
            return null;
        }

        auto sourceSymbolLocations = appender!(size_t[]);
        auto sourceSymbolFiles = appender!(string[]);
        auto result = appender!(Location[]);

        foreach (symbol; stuff.symbols.filter!q{a.location > 0})
        {
            sourceSymbolLocations ~= symbol.location;
            sourceSymbolFiles ~= symbol.symbolFile == "stdin" ? uri.path : symbol.symbolFile;
        }

        if (files is null)
        {
            foreach (sourceLocation, sourceFile; zip(sourceSymbolLocations.data,
                    sourceSymbolFiles.data))
            {
                auto sourceUri = Uri.fromPath(sourceFile);
                result ~= new Location(sourceUri.toString(),
                        Document.get(sourceUri).wordRangeAtByte(sourceLocation));
            }

            return result.data;
        }

        bool checkFileAndLocation(const string file, size_t location)
        {
            import std.path : filenameCmp;

            foreach (sourceLocation, sourceFile; zip(sourceSymbolLocations.data,
                    sourceSymbolFiles.data))
            {
                if (location == sourceLocation && filenameCmp(file, sourceFile) == 0)
                {
                    return true;
                }
            }

            return false;
        }

        foreach (fileUri; files)
        {
            auto document = Document.get(fileUri);
            request.fileName = fileUri.path;
            request.sourceCode = cast(ubyte[]) document.toString();
            auto tokens = getTokensForParser(request.sourceCode, LexerConfig(fileUri.path,
                    StringBehavior.compiler, WhitespaceBehavior.skip), &stringCache);

            foreach (ref token; tokens)
            {
                if (token.type == tok!"identifier" && token.text == sourceToken.text)
                {
                    request.cursorPosition = token.index + 1;
                    auto candidateStuff = getSymbolsForCompletion(request,
                            CompletionType.location, _allocator, &ra, stringCache, _cache);

                    scope (exit)
                    {
                        candidateStuff.destroy();
                    }

                    foreach (candidateSymbol; candidateStuff.symbols)
                    {
                        if (!includeDeclaration && checkFileAndLocation(fileUri.path, token.index))
                        {
                            continue;
                        }

                        const candidateSymbolFile = candidateSymbol.symbolFile == "stdin"
                            ? fileUri.path : candidateSymbol.symbolFile;

                        if (checkFileAndLocation(candidateSymbolFile, candidateSymbol.location))
                        {
                            result ~= new Location(fileUri.toString(),
                                    document.wordRangeAtByte(token.index));
                            break;
                        }
                    }
                }
            }
        }

        return result.data;
    }

    private MarkupContent getDocumentation(const string[][] detailsAndDocumentations)
    {
        import ddoc : Lexer, expand;
        import dls.protocol.definitions : MarkupKind;
        import std.array : appender, replace;
        import std.regex : regex, split;

        auto result = appender!string;
        bool putSeparator;

        foreach (dad; detailsAndDocumentations)
        {
            if (putSeparator)
            {
                result ~= "\n\n---\n\n";
            }
            else
            {
                putSeparator = true;
            }

            auto detail = dad[0];
            auto documentation = dad[1];
            auto content = documentation.split(regex(`\n-+(\n|$)`));
            bool isExample;

            if (detail.length > 0 && detailsAndDocumentations.length > 1)
            {
                result ~= "### ";
                result ~= detail;
                result ~= "\n\n";
            }

            foreach (chunk; content)
            {
                if (isExample)
                {
                    result ~= "```d\n";
                    result ~= chunk;
                    result ~= "\n```\n";
                }
                else
                {
                    result ~= expand(Lexer(chunk.replace("\n", " ")), macros);
                    result ~= '\n';
                }

                isExample = !isExample;
            }
        }

        return new MarkupContent(MarkupKind.markdown, result.data);
    }

    private static AutocompleteRequest getPreparedRequest(const Uri uri,
            const Position position, RequestKind kind)
    {
        import dls.util.document : Document;

        auto request = AutocompleteRequest();
        auto document = Document.get(uri);

        document.validatePosition(position);
        request.fileName = uri.path;
        request.kind = kind;
        request.sourceCode = cast(ubyte[]) document.toString();
        request.cursorPosition = document.byteAtPosition(position);

        return request;
    }

    private static Dub getDub(const Uri uri)
    {
        import std.file : isFile;
        import std.path : dirName;

        auto d = new Dub(isFile(uri.path) ? dirName(uri.path) : uri.path);
        d.loadPackage();
        return d;
    }
}
