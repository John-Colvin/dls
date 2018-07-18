module dls.tools.symbol_tool;

import dls.protocol.interfaces : CompletionItemKind, SymbolKind;
import dls.tools.tool : Tool;
import dsymbol.symbol : CompletionKind;
import std.algorithm : canFind;
import std.path : asNormalizedPath, buildNormalizedPath, dirName;

private string[string] macros;
private CompletionItemKind[CompletionKind] completionKinds;
private SymbolKind[CompletionKind] symbolKinds;

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

void useCompatCompletionItemKinds(CompletionItemKind[] items = [])
{
    //dfmt off
    immutable map = [
        CompletionKind.structName  : CompletionItemKind.class_,
        CompletionKind.enumMember  : CompletionItemKind.field,
        CompletionKind.packageName : CompletionItemKind.module_
    ];
    //dfmt on

    foreach (ck, cik; map)
    {
        if (!items.canFind(completionKinds[ck]))
        {
            completionKinds[ck] = cik;
        }
    }
}

void useCompatSymbolKinds(SymbolKind[] symbols = [])
{
    //dfmt off
    immutable map = [
        CompletionKind.structName : SymbolKind.class_,
        CompletionKind.enumMember : SymbolKind.field
    ];
    //dfmt on

    foreach (ck, sk; map)
    {
        if (!symbols.canFind(symbolKinds[ck]))
        {
            symbolKinds[ck] = sk;
        }
    }
}

class SymbolTool : Tool
{
    import dcd.common.messages : AutocompleteRequest, RequestKind;
    import dls.protocol.definitions : Location, MarkupContent, Position,
        TextDocumentItem;
    import dls.protocol.interfaces : CompletionItem, DocumentHighlight, Hover,
        SymbolInformation;
    import dls.util.document : Document;
    import dls.util.logger : logger;
    import dls.util.uri : Uri;
    import dsymbol.modulecache : ModuleCache;
    import dub.dub : Dub;
    import dub.platform : BuildPlatform;
    import std.algorithm : filter, map, reduce, sort, uniq;
    import std.array : appender, array, replace;
    import std.container : RedBlackTree;
    import std.conv : to;
    import std.file : exists, readText;
    import std.json : JSONValue;
    import std.range : chain;
    import std.regex : matchFirst;
    import std.typecons : nullable;

    version (Windows)
    {
        @property private static string[] _compilerConfigPaths()
        {
            import std.algorithm : splitter;
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
        private static immutable _compilerConfigPaths = [
            "/etc/dmd.conf", "/usr/local/etc/dmd.conf", "/etc/ldc2.conf",
            "/usr/local/etc/ldc2.conf", "/home/linuxbrew/.linuxbrew/etc/dmd.conf"
        ];
    }
    else
    {
        private static immutable string[] _compilerConfigPaths;
    }

    private ModuleCache*[string] _workspaceCaches;
    private ModuleCache*[string] _libraryCaches;

    @property private string[] defaultImportPaths()
    {
        import std.algorithm : each;
        import std.file : FileException;
        import std.regex : matchAll;

        string[] paths;

        foreach (confPath; _compilerConfigPaths)
        {
            if (exists(confPath))
            {
                try
                {
                    readText(confPath).matchAll(`-I[^\s"]+`)
                        .each!(m => paths ~= m.hit[2 .. $].replace("%@P%",
                                confPath.dirName).asNormalizedPath().to!string);
                    break;
                }
                catch (FileException e)
                {
                    // File doesn't exist or could't be read
                }
            }
        }

        version (Windows)
        {
            import std.algorithm : splitter;
            import std.process : environment;

            if (paths.length == 0)
            {
                foreach (path; splitter(environment["PATH"], ';'))
                {
                    if (exists(buildNormalizedPath(path, "ldc2.exe")))
                    {
                        paths = [buildNormalizedPath(path, "..", "import")];
                    }
                }
            }
        }
        else version (linux)
        {
            if (paths.length == 0)
            {
                foreach (path; ["/snap", "/var/lib/snapd/snap"])
                {
                    const dmdSnapPath = buildNormalizedPath(path, "dmd");
                    const ldcSnapIncludePath = buildNormalizedPath(path,
                            "ldc2", "current", "include", "d");

                    if (exists(dmdSnapPath))
                    {
                        paths = ["druntime", "phobos"].map!(end => buildNormalizedPath(dmdSnapPath,
                                "current", "import", end)).array;
                        break;
                    }
                    else if (exists(ldcSnapIncludePath))
                    {
                        paths = [ldcSnapIncludePath];
                        break;
                    }
                }
            }
        }

        return paths.sort().uniq().array;
    }

    this()
    {
        importDirectories!true("", defaultImportPaths);
    }

    ModuleCache*[] getRelevantCaches(Uri uri)
    {
        auto result = appender([getWorkspaceCache(uri)]);

        foreach (path; _libraryCaches.byKey)
        {
            if (path.length > 0)
            {
                result ~= _libraryCaches[path];
            }
        }

        result ~= _libraryCaches[""];

        return result.data;
    }

    ModuleCache* getWorkspaceCache(Uri uri)
    {
        import std.algorithm : startsWith;
        import std.path : pathSplitter;

        string[] cachePathParts;

        foreach (path; chain(_workspaceCaches.byKey, _libraryCaches.byKey))
        {
            auto splitter = pathSplitter(path);

            if (pathSplitter(uri.path).startsWith(splitter))
            {
                auto pathParts = splitter.array;

                if (pathParts.length > cachePathParts.length)
                {
                    cachePathParts = pathParts;
                }
            }
        }

        auto cachePath = buildNormalizedPath(cachePathParts);
        return cachePath in _workspaceCaches ? _workspaceCaches[cachePath]
            : _libraryCaches[cachePath];
    }

    void importPath(Uri uri)
    {
        import std.path : baseName;

        auto d = getDub(uri);
        auto packages = [d.project.rootPackage];

        foreach (sub; d.project.rootPackage.subPackages)
        {
            auto p = d.project.packageManager.getSubPackage(d.project.rootPackage,
                    baseName(sub.path), true);

            if (p !is null)
            {
                packages ~= p;
            }
        }

        foreach (p; packages)
        {
            const desc = p.describe(BuildPlatform.any, null, null);
            importDirectories!false(uri.path, desc.importPaths.length > 0
                    ? desc.importPaths.map!(path => buildNormalizedPath(p.path.toString(),
                        path)).array : [uri.path]);
            importSelections(Uri.fromPath(desc.path));
        }
    }

    void importSelections(Uri uri)
    {
        const d = getDub(uri);

        foreach (dep; d.project.dependencies)
        {
            auto paths = reduce!(q{a ~ b})(cast(string[])[],
                    dep.recipe.buildSettings.sourcePaths.values);
            importDirectories!true(dep.name,
                    paths.map!(path => buildNormalizedPath(dep.path.toString(), path)).array, true);
        }
    }

    void clearPath(Uri uri)
    {
        logger.infof("Clearing imports from %s", uri.path);
        (uri.path in _workspaceCaches ? _workspaceCaches : _libraryCaches).remove(uri.path);
    }

    void upgradeSelections(Uri uri)
    {
        import std.concurrency : spawn;
        import dls.protocol.messages.methods : Dls;

        logger.infof("Upgrading dependencies from %s", dirName(uri.path));

        spawn((string uriString) {
            import dls.protocol.jsonrpc : send;
            import dub.dub : UpgradeOptions;

            send(Dls.upgradeSelections_start);
            getDub(new Uri(uriString)).upgrade(UpgradeOptions.upgrade | UpgradeOptions.select);
            send(Dls.upgradeSelections_stop);
        }, uri.toString());
    }

    SymbolInformation[] symbol(string query, Uri uri = null)
    {
        import dsymbol.string_interning : internString;
        import dsymbol.symbol : DSymbol;
        import std.uni : toUpper;

        logger.infof(`Fetching symbols from %s with query "%s"`, uri is null
                ? "workspace" : uri.path, query);

        const simpleQuery = query.toUpper();
        auto result = new RedBlackTree!(SymbolInformation, q{a.name > b.name}, true);

        void collectSymbolInformations(Uri symbolUri, const(DSymbol)* symbol,
                string containerName = "")
        {
            if (symbol.symbolFile != symbolUri.path)
            {
                return;
            }

            if (symbol.name.data.toUpper().matchFirst(simpleQuery))
            {
                auto location = new Location(symbolUri,
                        Document[symbolUri].wordRangeAtByte(symbol.location));
                result.insert(new SymbolInformation(symbol.name,
                        symbolKinds[symbol.kind], location, containerName.nullable));
            }

            foreach (s; symbol.getPartsByName(internString(null)))
            {
                collectSymbolInformations(symbolUri, s, symbol.name);
            }
        }

        static Uri[] getModuleUris(ModuleCache* cache)
        {
            import std.file : SpanMode, dirEntries;

            auto result = appender!(Uri[]);

            foreach (rootPath; cache.getImportPaths())
            {
                foreach (entry; dirEntries(rootPath, "*.{d,di}", SpanMode.breadth))
                {
                    result ~= Uri.fromPath(entry.name);
                }
            }

            return result.data;
        }

        foreach (cache; _workspaceCaches.byValue)
        {
            auto moduleUris = uri is null ? getModuleUris(cache) : [uri];

            foreach (moduleUri; moduleUris)
            {
                auto moduleSymbol = cache.cacheModule(moduleUri.path);

                if (moduleSymbol !is null)
                {
                    const closed = openDocument(moduleUri);

                    foreach (symbol; moduleSymbol.getPartsByName(internString(null)))
                    {
                        collectSymbolInformations(moduleUri, symbol);
                    }

                    closeDocument(moduleUri, closed);
                }
            }
        }

        return result.array;
    }

    CompletionItem[] completion(Uri uri, Position position)
    {
        import dcd.common.messages : AutocompleteResponse, CompletionType;
        import dcd.server.autocomplete : complete;
        import std.algorithm : chunkBy;

        logger.infof("Fetching completions for %s at position %s,%s", uri.path,
                position.line, position.character);

        auto request = getPreparedRequest(uri, position);
        request.kind = RequestKind.autocomplete;

        static bool compareCompletionsLess(AutocompleteResponse.Completion a,
                AutocompleteResponse.Completion b)
        {
            //dfmt off
            return a.identifier < b.identifier ? true
                : a.identifier > b.identifier ? false
                : a.symbolFilePath < b.symbolFilePath ? true
                : a.symbolFilePath > b.symbolFilePath ? false
                : a.symbolLocation < b.symbolLocation;
            //dfmt on
        }

        static bool compareCompletionsEqual(AutocompleteResponse.Completion a,
                AutocompleteResponse.Completion b)
        {
            return a.symbolFilePath == b.symbolFilePath && a.symbolLocation == b.symbolLocation;
        }

        auto completionsList = chain(_workspaceCaches.byValue, _libraryCaches.byValue).map!(
                cache => complete(request, *cache))
            .filter!(a => a.completionType == CompletionType.identifiers)
            .map!q{a.completions};

        if (completionsList.empty)
        {
            return [];
        }

        return completionsList.reduce!q{a ~ b}
            .sort!compareCompletionsLess
            .uniq!compareCompletionsEqual
            .chunkBy!q{a.identifier == b.identifier}
            .map!((resultGroup) {
                import std.uni : toLower;

                auto firstResult = resultGroup.front;
                auto item = new CompletionItem(firstResult.identifier);
                item.kind = completionKinds[firstResult.kind.to!CompletionKind];
                item.detail = firstResult.definition;

                string[][] data;

                foreach (res; resultGroup)
                {
                    if (res.documentation.length > 0 && res.documentation.toLower() != "ditto")
                    {
                        data ~= [res.definition, res.documentation];
                    }
                }

                if (data.length > 0)
                {
                    item.data = JSONValue(data);
                }

                return item;
            })
            .array;
    }

    CompletionItem completionResolve(CompletionItem item)
    {
        if (!item.data.isNull)
        {
            item.documentation = getDocumentation(
                    item.data.array.map!q{ [a[0].str, a[1].str] }.array);
            item.data.nullify();
        }

        return item;
    }

    Hover hover(Uri uri, Position position)
    {
        import dcd.server.autocomplete : getDoc;

        logger.infof("Fetching documentation for %s at position %s,%s",
                uri.path, position.line, position.character);

        auto request = getPreparedRequest(uri, position);
        request.kind = RequestKind.doc;
        auto completions = getRelevantCaches(uri).map!(cache => getDoc(request,
                *cache).completions)
            .reduce!q{a ~ b}
            .map!q{a.documentation}
            .filter!q{a.length > 0}
            .array
            .sort().uniq();

        return completions.empty ? null
            : new Hover(getDocumentation(completions.map!q{ ["", a] }.array));
    }

    Location definition(Uri uri, Position position)
    {
        import dcd.common.messages : AutocompleteResponse;
        import dcd.server.autocomplete : findDeclaration;
        import std.algorithm : find;

        logger.infof("Finding declaration for %s at position %s,%s", uri.path,
                position.line, position.character);

        auto request = getPreparedRequest(uri, position);
        request.kind = RequestKind.symbolLocation;
        AutocompleteResponse[] results;

        foreach (cache; getRelevantCaches(uri))
        {
            results ~= findDeclaration(request, *cache);
        }

        results = results.find!q{a.symbolFilePath.length > 0}.array;

        if (results.length == 0)
        {
            return null;
        }

        auto resultUri = results[0].symbolFilePath == "stdin" ? uri
            : Uri.fromPath(results[0].symbolFilePath);
        openDocument(resultUri);

        return new Location(resultUri,
                Document[resultUri].wordRangeAtByte(results[0].symbolLocation));
    }

    DocumentHighlight[] highlight(Uri uri, Position position)
    {
        import dcd.server.autocomplete.localuse : findLocalUse;
        import dls.protocol.interfaces : DocumentHighlightKind;

        logger.infof("Highlighting usages for %s at position %s,%s", uri.path,
                position.line, position.character);

        static bool highlightLess(in DocumentHighlight a, in DocumentHighlight b)
        {
            return a.range.start.line < b.range.start.line
                || (a.range.start.line == b.range.start.line
                        && a.range.start.character < b.range.start.character);
        }

        auto request = getPreparedRequest(uri, position);
        request.kind = RequestKind.localUse;
        auto result = new RedBlackTree!(DocumentHighlight, highlightLess, false);

        foreach (cache; getRelevantCaches(uri))
        {
            auto localUse = findLocalUse(request, *cache);
            result.insert(localUse.completions.map!((res) => new DocumentHighlight(
                    Document[uri].wordRangeAtByte(res.symbolLocation), (res.symbolLocation == localUse.symbolLocation
                    ? DocumentHighlightKind.write : DocumentHighlightKind.text).nullable)));
        }

        return result.array;
    }

    package void importDirectories(bool isLibrary)(string root, string[] paths, bool refresh = false)
    {
        import dsymbol.modulecache : ASTAllocator;
        import std.algorithm : canFind;

        logger.infof(`Importing into cache "%s": %s`, root, paths);

        static if (isLibrary)
        {
            alias caches = _libraryCaches;
        }
        else
        {
            alias caches = _workspaceCaches;
        }

        if (refresh && (root in caches))
        {
            caches.remove(root);
        }

        if (!(root in caches))
        {
            caches[root] = new ModuleCache(new ASTAllocator());
        }

        foreach (path; paths)
        {
            if (!caches[root].getImportPaths().canFind(path))
            {
                caches[root].addImportPaths([path]);
            }
        }
    }

    private MarkupContent getDocumentation(string[][] detailsAndDocumentations)
    {
        import ddoc : Lexer, expand;
        import dls.protocol.definitions : MarkupKind;
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

    private static AutocompleteRequest getPreparedRequest(Uri uri, Position position)
    {
        auto request = AutocompleteRequest();
        auto document = Document[uri];

        request.fileName = uri.path;
        request.sourceCode = cast(ubyte[]) document.toString();
        request.cursorPosition = document.byteAtPosition(position);

        return request;
    }

    private static Dub getDub(Uri uri)
    {
        import std.file : isFile;

        auto d = new Dub(isFile(uri.path) ? dirName(uri.path) : uri.path);
        d.loadPackage();
        return d;
    }

    private static bool openDocument(Uri docUri)
    {
        auto closed = Document[docUri] is null;

        if (closed)
        {
            auto doc = new TextDocumentItem();
            doc.uri = docUri;
            doc.languageId = "d";
            doc.text = readText(docUri.path);
            Document.open(doc);
        }

        return closed;
    }

    private static void closeDocument(Uri docUri, bool wasClosed)
    {
        import dls.protocol.definitions : TextDocumentIdentifier;

        if (wasClosed)
        {
            auto docIdentifier = new TextDocumentIdentifier();
            docIdentifier.uri = docUri;
            Document.close(docIdentifier);
        }
    }
}
