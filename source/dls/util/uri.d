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

module dls.util.uri;

class Uri
{
    import dls.protocol.definitions : DocumentUri;
    import std.regex : regex;

    private static enum _reg = regex(
                `(?:([\w-]+)://)?([\w.]+(?::\d+)?)?([^\?#]+)(?:\?([\w=&]+))?(?:#([\w-]+))?`);
    private string _uri;
    private string _scheme;
    private string _authority;
    private string _path;
    private string _query;
    private string _fragment;

    @property string path() const
    {
        return _path;
    }

    this(DocumentUri uri)
    {
        import std.conv : to;
        import std.regex : matchAll;
        import std.uri : decodeComponent;
        import std.utf : toUTF32;

        auto matches = matchAll(decodeComponent(uri.toUTF32()), _reg);

        //dfmt off
        _uri        = uri;
        _scheme     = matches.front[1];
        _authority  = matches.front[2];
        _path       = matches.front[3].to!string.normalized;
        _query      = matches.front[4];
        _fragment   = matches.front[5];
        //dfmt on
    }

    override string toString() const
    {
        return _uri;
    }

    static Uri fromPath(string path)
    {
        import std.algorithm : startsWith;
        import std.format : format;
        import std.string : tr;
        import std.uri : encode;

        const uriPath = path.tr(`\`, `/`);
        return new Uri(encode(format!"file://%s%s"(uriPath.startsWith('/') ? "" : "/", uriPath)));
    }

    alias toString this;
}

string normalized(const string path)
{
    import std.conv : to;
    import std.path : asNormalizedPath;

    string res;

    version (Windows)
    {
        import std.algorithm : startsWith;
        import std.path : driveName, stripDrive;
        import std.uni : asUpperCase;

        if (path.startsWith('/') || path.startsWith('\\'))
        {
            return path[1 .. $].normalized;
        }

        res = (driveName(path).asUpperCase.to!string ~ stripDrive(path));
    }
    else
    {
        res = path;
    }

    return res.asNormalizedPath.to!string;
}
