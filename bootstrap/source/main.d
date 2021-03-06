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

private enum Method : string
{
    auto_ = "auto",
    download = "download",
    build = "build"
}

shared static this()
{
    import dls.util.setup : initialSetup;

    initialSetup();
}

int main(string[] args)
{
    import dls.bootstrap : canDownloadDls, buildDls, downloadDls, linkDls;
    import dls.util.constants : Tr;
    import dls.util.i18n : tr;
    import std.conv : to;
    import std.file : thisExePath;
    import std.format : format;
    import std.getopt : getopt, defaultGetoptPrinter;
    import std.path : dirName;
    import std.stdio : stderr, stdout;

    Method method;
    bool check;
    bool localization;
    bool progress;

    try
    {
        //dfmt off
        auto info = getopt(args,
                "method|m",
                format(tr(Tr.bootstrap_help_method), cast(string) Method.auto_, Method.download, Method.build)
                ~ format(tr(Tr.bootstrap_help_method_auto), cast(string) Method.auto_, Method.download, Method.build)
                ~ format!" [%s = %s]"(tr(Tr.bootstrap_help_default), cast(string) method),
                &method,
                "check|c",
                format!"%s [%s = %s]"(tr(Tr.bootstrap_help_check), tr(Tr.bootstrap_help_default), check),
                &check,
                "localization|l",
                format!"%s [%s = %s]"(tr(Tr.bootstrap_help_localization), tr(Tr.bootstrap_help_default), localization),
                &localization,
                "progress|p",
                format(tr(Tr.bootstrap_help_progress), Method.download)
                ~ format!" [%s = %s]"(tr(Tr.bootstrap_help_default), progress),
                &progress);
        //dfmt on

        if (info.helpWanted)
        {
            defaultGetoptPrinter("DLS bootstrap utility", info.options);
            return 0;
        }
    }
    catch (Exception e)
    {
        stderr.writeln(e.message);
        return 1;
    }

    string output;
    int status;

    if (check)
    {
        const ok = method != Method.download || canDownloadDls;
        output = ok.to!string;
        status = ok ? 0 : 1;
    }
    else
    {
        if (localization)
        {
            stderr.rawWrite("installing:" ~ tr(Tr.bootstrap_installDls_installing) ~ '\t');
            stderr.rawWrite("downloading:" ~ tr(Tr.bootstrap_installDls_downloading) ~ '\t');
            stderr.rawWrite("extracting:" ~ tr(Tr.bootstrap_installDls_extracting) ~ '\n');
            stderr.flush();
        }

        const printSize = progress ? (size_t size) {
            stderr.rawWrite(size.to!string ~ '\n');
            stderr.flush();
        } : null;
        const printExtract = progress ? () {
            stderr.rawWrite("extract\n");
            stderr.flush();
        } : null;

        (method == Method.download || (method == Method.auto_ && canDownloadDls)) ? downloadDls(printSize,
                printSize, printExtract) : buildDls(thisExePath.dirName.dirName);
        output = linkDls();
    }

    stdout.rawWrite(output);

    return status;
}
