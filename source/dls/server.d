module dls.server;

import dls.protocol.handlers;
import dls.protocol.jsonrpc;

shared static this()
{
    import std.algorithm : map;
    import std.array : join, split;
    import std.meta : AliasSeq;
    import std.traits : hasUDA, select;
    import std.typecons : tuple;
    import std.string : capitalize;

    foreach (modName; AliasSeq!("general", "client", "text_document", "window", "workspace"))
    {
        mixin("import dls.protocol.messages" ~ (modName.length ? "." ~ modName : "") ~ ";");
        mixin("alias mod = dls.protocol.messages" ~ (modName.length ? "." ~ modName : "") ~ ";");

        foreach (thing; __traits(allMembers, mod))
        {
            mixin("alias t = " ~ thing ~ ";");

            static if (isHandler!t)
            {
                enum attrs = tuple(__traits(getAttributes, t));
                enum attrsWithDefaults = tuple(modName[0] ~ modName.split('_')
                            .map!capitalize().join()[1 .. $], thing, attrs.expand);
                enum parts = tuple(attrsWithDefaults[attrs.length > 0 ? 2 : 0],
                            attrsWithDefaults[attrs.length > 1 ? 3 : 1]);
                enum method = select!(parts[0].length != 0)(parts[0] ~ "/", "") ~ parts[1];

                pushHandler(method, &t);
            }
        }
    }
}

abstract class Server
{
    import dls.protocol.interfaces : InitializeParams;
    import dls.util.logger : logger;
    import std.algorithm : find, findSplit;
    import std.json : JSONValue;
    import std.typecons : Nullable, nullable;

    static bool initialized = false;
    static bool shutdown = false;
    static bool exit = false;
    private static InitializeParams _initState;

    @property static InitializeParams initState()
    {
        return _initState;
    }

    @property static void initState(InitializeParams params)
    {
        _initState = params;

        debug
        {
            logger.trace = InitializeParams.Trace.verbose;
        }
        else
        {
            logger.trace = params.trace;
        }
    }

    @property static InitializeParams.InitializationOptions initOptions()
    {
        return _initState.initializationOptions.isNull
            ? new InitializeParams.InitializationOptions() : _initState.initializationOptions;
    }

    static void loop()
    {
        import std.array : appender;
        import std.conv : to;
        import std.stdio : stdin;
        import std.string : strip, stripRight;

        while (!stdin.eof && !exit)
        {
            string[string] headers;
            string line;

            do
            {
                auto lineAppender = appender!(char[]);
                auto charBuffer = new char[1];
                bool cr;
                bool lf;

                lineAppender.clear();

                do
                {
                    auto res = stdin.rawRead(charBuffer);

                    if (res.length == 0)
                    {
                        break;
                    }

                    lineAppender ~= res[0];

                    if (cr)
                    {
                        lf = res[0] == '\n';
                    }

                    cr = res[0] == '\r';
                }
                while (!lf);

                line = lineAppender.data.stripRight().to!string;
                auto parts = line.findSplit(":");

                if (parts[1].length > 0)
                {
                    headers[parts[0].to!string] = parts[2].to!string;
                }
            }
            while (line.length > 0);

            if (headers.length == 0)
            {
                continue;
            }

            if ("Content-Length" !in headers)
            {
                logger.error("No valid Content-Length section in header");
                continue;
            }

            auto contentLengthResult = headers["Content-Length"];
            static char[] buffer;
            const contentLength = contentLengthResult.strip().to!size_t;
            buffer.length = contentLength;
            const content = stdin.rawRead(buffer);

            handleJSON(content);
        }
    }

    private static void handleJSON(in char[] content)
    {
        import dls.protocol.jsonrpc : send, sendError;
        import dls.util.json : convertFromJSON;
        import std.algorithm : canFind;
        import std.json : JSONException, parseJSON;

        RequestMessage request;

        try
        {
            const json = parseJSON(content);

            if ("method" in json)
            {
                if ("id" in json)
                {
                    request = convertFromJSON!RequestMessage(json);

                    if (!shutdown && (initialized || ["initialize"].canFind(request.method)))
                    {
                        send(request.id, handler!RequestHandler(request.method)(request.params));
                    }
                    else
                    {
                        sendError(ErrorCodes.serverNotInitialized, request, JSONValue());
                    }
                }
                else
                {
                    auto notification = convertFromJSON!NotificationMessage(json);

                    if (initialized)
                    {
                        handler!NotificationHandler(notification.method)(notification.params);
                    }
                }
            }
            else
            {
                auto response = convertFromJSON!ResponseMessage(json);

                if (response.error.isNull)
                {
                    handler!ResponseHandler(response.id.str)(response.id.str, response.result);
                }
                else
                {
                    logger.error(response.error.message);
                }
            }
        }
        catch (JSONException e)
        {
            logger.errorf("%s: %s", ErrorCodes.parseError[0], e.message);
            sendError(ErrorCodes.parseError, request, JSONValue(e.message));
        }
        catch (HandlerNotFoundException e)
        {
            logger.errorf("%s: %s", ErrorCodes.methodNotFound[0], e.message);
            sendError(ErrorCodes.methodNotFound, request, JSONValue(e.message));
        }
        catch (Exception e)
        {
            logger.errorf("%s: %s", ErrorCodes.internalError[0], e.message);
            sendError(ErrorCodes.internalError, request, JSONValue(e.message));
        }
    }
}
