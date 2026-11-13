#!/usr/bin/env python3
"""Exercise actual opt-in zsign policy/Init/bundle branches with synthetic fixtures.

No existing credentials/profiles or p12 are opened. Temporary self-signed PEM
certificates and CMS *test metadata* are generated; no app/binary is signed. The
bundle path uses an instrumented Mach-O signer that only records dispatch.
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import os
import plistlib
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
SRC = ROOT / 'ipa-signing-work/tools/zsign-src/src'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source-dir', type=Path, help='Native src directory; defaults to the existing local signer checkout')
parser.add_argument('--candidate', type=Path, help='Optional separate candidate binary for pre-signing failure routes')
parser.add_argument('--sanitize', action='store_true', help='Compile synthetic actual-source harness with AddressSanitizer')
args = parser.parse_args()
if args.source_dir:
    SRC = args.source_dir.resolve(strict=True)


def run(command, **kwargs):
    result = subprocess.run(command, capture_output=True, **kwargs)
    if result.returncode:
        print(result.stdout.decode(errors="replace") if isinstance(result.stdout, bytes) else result.stdout)
        print(result.stderr.decode(errors="replace") if isinstance(result.stderr, bytes) else result.stderr)
        raise RuntimeError(f"Synthetic regression command failed ({result.returncode})")
    return result


def block(source, marker):
    start = source.index(marker)
    opening = source.index('{', start)
    position, depth = opening + 1, 1
    while depth:
        depth += (source[position] == '{') - (source[position] == '}')
        position += 1
    return source[start:position] + '\n'


TEST = r'''
#include "strict_signing.h"
#include "bundle.h"
#include "macho.h"
#include "signing.h"
#include <sys/wait.h>
#include <fstream>
extern vector<pair<string, ZSignAsset*>> signingCalls;
int checks = 0;
bool boundedChild(const function<bool()>& operation) {
    const pid_t child=fork(); if (child<0) return false;
    if (child==0) { alarm(2); _exit(operation() ? 0 : 1); }
    int status=0; return waitpid(child,&status,0)==child && WIFEXITED(status) && WEXITSTATUS(status)==0;
}
void check(bool value, const char* name) { ++checks; if (!value) { cerr << "FAIL " << name << endl; exit(1); } }
string get(const string& path) { string value; check(ZStrictReadFile(path, 8388608, value), "owned fixture readable"); return value; }
string xml(const string& body) { return "<?xml version=\"1.0\"?><plist version=\"1.0\">" + body + "</plist>"; }
string doctype(const string& document, const string& declaration) { string result=document; result.insert(result.find("?>")+2,declaration); return result; }
string record(const string& id) { return "{\"bundle_id\":\"" + id + "\",\"profile_path\":\"profile\",\"entitlements_path\":\"entitlements\"}"; }
void file(const string& path, const string& data) { check(ZFile::WriteFile(path.c_str(),data), "write owned fixture"); }
void mkdir(const string& path) { check(ZFile::CreateFolder(path.c_str()), "create owned fixture"); }
void info(const string& path, const string& id, const string& executable) {
    jvalue value; value["CFBundleIdentifier"] = id; value["CFBundleExecutable"] = executable; value["CFBundleVersion"] = "1";
    string text; value.style_write_plist(text); file(path + "/Info.plist", text);
}
void macho(const string& path, uint32_t type) { uint32_t header[8] = {MH_MAGIC_64, 0,0,type,0,0,0,0}; file(path,string(reinterpret_cast<char*>(header),sizeof(header))); }
int main(int argc, char** argv) {
    ZLog::SetLogLever(ZLog::E_NONE);
    check(argc == 2, "owned fixture directory supplied");
    const string directory = argv[1];
    vector<ZStrictBundleSpec> specs;
    check(ZStrictParseManifest("[" + record("test.main") + "," + record("test.main.NotificationService") + "]", directory, specs), "valid two-record manifest");
    check(specs.size() == 2 && specs[0].profilePath == directory + "/profile", "relative profile path resolution");
    for (const string& bad : {string("[]"), string("{}"), "[" + record("test.main") + "," + record("test.main") + "]",
         "[" + record("test.main") + "]true", "[" + record("test.main") + ",]", "[" + record("test.*") + "]",
         string("[{\"bundle_id\":1,\"profile_path\":\"p\",\"entitlements_path\":\"e\"}]"),
         string("[{\"bundle_id\":\"test.main\",\"bundle_id\":\"test.other\",\"profile_path\":\"p\",\"entitlements_path\":\"e\"}]"),
         string("[{\"bundle_id\":\"test.main\",\"bundle\\u005fid\":\"test.other\",\"profile_path\":\"p\",\"entitlements_path\":\"e\"}]"),
         string("[{\"bundle_id\":\"test.main\",\"profile_path\":\"p\\u0000tail\",\"entitlements_path\":\"e\"}]")})
        check(!ZStrictParseManifest(bad,directory,specs), "malformed/duplicate/trailing manifest rejects");
    check(ZStrictParseManifest(" \n[" + record("test.main") + "]\t ",directory,specs), "manifest outer whitespace");
    check(!ZStrictParseManifest(string(65537,' '),directory,specs), "manifest size bound");
    check(!ZStrictBundleId(".bad") && !ZStrictBundleId("bad..id") && !ZStrictBundleId("bad:id"), "bundle ID grammar");
    string bounded;
    file(directory+"/empty", ""); file(directory+"/bounded", "12345678901");
    check(!ZStrictReadFile(directory+"/empty",10,bounded), "empty input file rejects");
    check(!ZStrictReadFile(directory+"/bounded",10,bounded), "oversized input rejects before allocation");
    check(ZStrictReadFile(directory+"/bounded",11,bounded) && bounded == "12345678901", "exact bounded file length accepted");
    check(!ZStrictReadFile(directory,100,bounded), "input directory rejects");
    jvalue ent;
    check(ZStrictReadEntitlements(xml("<dict><key>escaped</key><string>A&amp;B&#49;</string><key>array</key><array><true/><false/><integer>-3</integer><real>1.5</real><dict><key>x</key><string/></dict></array></dict>"),ent), "system XML decoding and supported typed values");
    check(ent["escaped"].as_string() == "A&B1" && ent["array"][2].as_int64() == -3 && ent["array"][4]["x"].is_string(), "decoded values constructed correctly");
    const string dtd = "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">";
    check(ZStrictReadEntitlements(doctype(xml("<dict><key>x</key><string>v</string></dict>"),dtd),ent), "standard nonloading plist DTD");
    for (const string& body : {
         string("<dict><key>x</key><string>a</string><key>x</key><string>b</string></dict>"),
         string("<dict><key>x</key><string>a</string><key>&#120;</key><string>b</string></dict>"),
         string("<dict><key>x</key><string>a</string><key>&#x78;</key><string>b</string></dict>"),
         string("<dict><key>1</key><string>a</string><key>&#49;</key><string>b</string></dict>"),
         string("<dict><key>nested</key><dict><key>x</key><true/><key>x</key><false/></dict></dict>"),
         string("<dict><key>x</key><integer>bad</integer></dict>"), string("<dict><key>x</key><integer>9223372036854775808</integer></dict>"),
         string("<dict><key>x</key><real>NaN</real></dict>"), string("<dict><key>x</key><real>0x1p2</real></dict>"),
         string("<dict><key>x</key><true>text</true></dict>"), string("<dict><key>x</key></dict>"),
         string("<dict><string>value</string></dict>"), string("<array/>"), string("<dict><key>x</key><string>&bogus;</string></dict>")})
        check(!ZStrictReadEntitlements(xml(body),ent), "malformed typed/duplicate XML rejects");
    check(!ZStrictReadEntitlements(xml("<dict/>") + xml("<dict/>"),ent), "trailing second XML root rejects");
    check(!ZStrictReadEntitlements(xml("<dict/>") + "junk",ent), "trailing XML text rejects");
    check(!ZStrictReadEntitlements("bplist00anything",ent), "binary entitlement plist rejected");
    check(!ZStrictReadEntitlements(string(1048577,' '),ent), "entitlement size bound");
    check(!ZStrictReadEntitlements(doctype(xml("<dict><key>x</key><string>&foo;</string></dict>"),"<!DOCTYPE plist [<!ENTITY foo 'value'>]>"),ent), "internal entity DTD rejects");
    check(!ZStrictReadEntitlements(doctype(xml("<dict/>"),"<!DOCTYPE plist SYSTEM 'file:///nonexistent-private-data'>"),ent), "external DTD rejects without loading");
    check(!ZStrictReadEntitlements(xml("<dict><key>x</key><string xmlns='urn:other'>v</string></dict>"),ent), "namespace/attribute ambiguity rejects");
    check(ZStrictReadEntitlements(" \n" + xml("<dict><key>x</key><string>v</string></dict>") + "\t",ent), "XML outer whitespace");
    jvalue metadata, legacyMetadata;
    const string duplicatedInfo = xml("<dict><key>CFBundleIdentifier</key><string>test.main</string><key>CFBundleIdentifier</key><string>test.other</string><key>CFBundleExecutable</key><string>Main</string></dict>");
    check(legacyMetadata.read_plist(duplicatedInfo) && legacyMetadata["CFBundleIdentifier"].as_string() == "test.other", "legacy XML metadata confirms duplicate overwrite behavior");
    check(!ZStrictReadMetadata(duplicatedInfo,metadata), "strict XML Info duplicate ID rejects");
    check(!ZStrictReadMetadata(xml("<dict><key>CFBundleIdentifier</key><string>test.main</string><key>&#67;FBundleIdentifier</key><string>test.other</string></dict>"),metadata), "strict Info normalized XML key duplicate rejects");
    check(ZStrictReadMetadata(get(directory+"/valid-info.binary"),metadata) && metadata["CFBundleIdentifier"].as_string() == "test.main", "valid binary Info metadata preserved");
    check(legacyMetadata.read_plist(get(directory+"/duplicate-info.binary")) && legacyMetadata["CFBundleIdentifier"].as_string() == "test.other", "legacy binary duplicate overwrite unchanged");
    check(!ZStrictReadMetadata(get(directory+"/duplicate-info.binary"),metadata), "strict duplicate binary dictionary keys reject");
    check(!ZStrictReadMetadata(get(directory+"/nul-info.binary"),metadata), "strict NUL binary metadata rejects");
    check(!ZStrictReadMetadata(get(directory+"/unicode-duplicate-info.binary"),metadata), "strict equivalent ASCII/UTF16 binary keys reject");
    check(ZStrictReadMetadata(get(directory+"/emoji-info.binary"),metadata) && metadata["CFBundleDisplayName"].as_string() == "SuperGram \xf0\x9f\x90\xbe", "valid paired UTF16 binary metadata preserves supplementary scalar");
    for (const string& name : {string("unicode-high"),string("unicode-low"),string("unicode-high-ascii"),string("unicode-reversed"),string("unicode-nul")})
        check(!ZStrictReadMetadata(get(directory+"/"+name+".binary"),metadata), "malformed UTF16 scalar pair rejects in strict mode");
    check(legacyMetadata.read_plist(get(directory+"/unicode-high.binary")), "legacy surrogate behavior unchanged");
    check(!ZStrictReadMetadata(get(directory+"/emoji-duplicate.binary"),metadata), "equivalent paired surrogate/UTF8 decoded keys reject");
    check(ZStrictReadMetadata(get(directory+"/shared-small.binary"),metadata), "bounded shared binary references remain supported");
    check(!ZStrictReadMetadata(get(directory+"/shared-large.binary"),metadata), "tiny DAG cannot expand past strict work bound");
    for (const string& name : {string("shared-data-wide"),string("shared-ascii-wide"),string("shared-unicode-wide")})
        check(!ZStrictReadMetadata(get(directory+"/"+name+".binary"),metadata), "repeated binary leaves reject at aggregate decoded byte bound before allocation");
    check(ZStrictReadMetadata(get(directory+"/shared-data-control.binary"),metadata), "bounded repeated data leaf control remains valid");
    check(ZStrictReadMetadata(get(directory+"/shared-data-near-limit.binary"),metadata), "near-limit repeated data leaf control remains valid");
    jpreader byteReusable(true); const string repeatedData=get(directory+"/shared-data-control.binary");
    check(byteReusable.parse_binary(repeatedData.data(),repeatedData.size(),metadata) && byteReusable.parse_binary(repeatedData.data(),repeatedData.size(),metadata), "strict decoded byte budget resets per parse");
    legacyMetadata.clear(); check(legacyMetadata.read_plist(get(directory+"/shared-ascii-wide.binary")), "legacy repeated-leaf allocation behavior unchanged with bounded16MiB fixture"); legacyMetadata.clear();
    check(legacyMetadata.read_plist(get(directory+"/shared-large.binary")), "legacy binary reference handling unchanged");
    check(!ZStrictReadMetadata(get(directory+"/cyclic.binary"),metadata), "cyclic binary references reject within depth bound");
    check(!ZStrictReadMetadata(get(directory+"/deep.binary"),metadata), "over-deep binary metadata rejects");
    jpreader reusable(true); const string sharedSmall=get(directory+"/shared-medium.binary");
    check(reusable.parse_binary(sharedSmall.data(),sharedSmall.size(),metadata) && reusable.parse_binary(sharedSmall.data(),sharedSmall.size(),metadata), "strict reader work budget resets per parse");
    for (const string& name : {string("real-nan"),string("real-infinity"),string("float-nan"),string("date-nan"),string("date-infinity"),string("date-huge"),string("date-negative-huge"),string("null-array"),string("uid"),string("unknown-null")})
        check(!ZStrictReadMetadata(get(directory+"/"+name+".binary"),metadata), "strict invalid binary typed metadata rejects");
    check(legacyMetadata.read_plist(get(directory+"/real-nan.binary")), "legacy nonfinite real behavior unchanged");
    check(ZStrictReadMetadata(get(directory+"/date-zero.binary"),metadata) && metadata["date"].as_date()==978307200, "strict binary absolute date zero matches Apple UTC reference");
    check(legacyMetadata.read_plist(get(directory+"/date-zero.binary")) && legacyMetadata["date"].as_date()==978278400, "legacy date epoch behavior unchanged");
    jvalue xmlDate;
    check(ZStrictReadMetadata(get(directory+"/known-date.xml"),xmlDate) && ZStrictReadMetadata(get(directory+"/known-date.binary"),metadata) && metadata["date"].as_date()==xmlDate["date"].as_date() && metadata["date"].as_date()==1791504000, "strict XML/binary known dates agree with system plistlib UTC fixture");
    check(ZStrictReadMetadata(xml("<dict><key>date</key><date>2026-10-09T00:00:00Z</date><key>data</key><data>QQ==</data></dict>"),metadata) && metadata["date"].is_date() && metadata["data"].as_data() == "A", "strict standard XML metadata date/data nodes");
    check(!ZStrictReadMetadata(xml("<dict><key>date</key><date>2026-02-31T00:00:00Z</date></dict>"),metadata), "invalid XML metadata date rejects");
    check(!ZStrictReadMetadata(xml("<dict><key>data</key><data>A===</data></dict>"),metadata), "invalid XML metadata base64 rejects");
    jvalue profile; check(profile.read_plist(get(directory + "/main.profile.plist")), "synthetic profile parser");
    check(ZStrictReadEntitlements(get(directory + "/main.entitlements"),ent), "synthetic main entitlements parse");
    check(ZStrictValidateEntitlements(profile,ent,"test.main"), "matching exact profile and rights");
    string canonical;
    check(ZStrictCanonicalEntitlements(ent,canonical), "current signed rights preserve exact canonical system/legacy semantics");
    jvalue systemCanonical, legacyCanonical;
    check(ZStrictReadEntitlements(canonical,systemCanonical) && legacyCanonical.read_plist(canonical) && ZStrictExactValue(ent,systemCanonical) && ZStrictExactValue(ent,legacyCanonical), "canonical signed rights have matching XML and DER input trees");
    check(ZSign::_DER(jvalue(false)) == string("\x01\x01\x00",3) && ZSign::_DER(jvalue(true)) == string("\x01\x01\xff",3), "actual DER encodes zero/true boolean values");
    check(ZSign::_DER(jvalue("abc")) == string("\x0c\x03" "abc",5) && ZSign::_DER(jvalue("")) == string("\x0c\x00",2), "actual DER typed string/empty string output");
    jvalue array(jvalue::E_ARRAY); array.push_back(false); array.push_back("abc");
    check(ZSign::_DER(array) == string("\x30\x08\x01\x01\x00\x0c\x03" "abc",10), "actual DER array preserves typed order");
    check(ZSign::_DER(jvalue(jvalue::E_ARRAY)) == string("\x30\x00",2) && ZSign::_DER(jvalue(jvalue::E_OBJECT)) == string("\xb0\x00",2), "actual DER zero-length array/dictionary output");
    string derSlot;
    check(ZSign::SlotBuildDerEntitlements(canonical,derSlot) && derSlot.size()>8 && derSlot.compare(0,4,string("\xfa\xde\x71\x72",4))==0 && derSlot.substr(derSlot.size()-ZSign::_DER(ent).size())==ZSign::_DER(ent), "actual DER slot encodes exactly the validated rights tree");
    for (const string& unsupported : {string("<integer>0</integer>"),string("<integer>-1</integer>"),string("<real>1e300</real>"),string("<string>data:QQ==</string>"),string("<string>date:2026-10-09T00:00:00Z</string>"),string("<string>A&amp;B</string>")}) {
        jvalue desired;
        check(ZStrictReadEntitlements(xml("<dict><key>value</key>"+unsupported+"</dict>"),desired) && !ZStrictCanonicalEntitlements(desired,canonical), "unsupported DER type/string promotion/entity semantics reject before serialization/signing");
    }
    jvalue changed = ent; changed["application-identifier"] = "SYNTHETIC.test.main.NotificationService";
    check(!ZStrictValidateEntitlements(profile,changed,"test.main"), "main identifier cannot leak into another bundle");
    changed = profile; changed["Entitlements"]["application-identifier"] = "OTHER.SYNTHETIC.test.main";
    check(!ZStrictValidateEntitlements(changed,ent,"test.main"), "suffix profile trap rejects");
    changed = ent; changed["get-task-allow"] = 0;
    check(!ZStrictValidateEntitlements(profile,changed,"test.main"), "boolean integer coercion rejects");
    changed = ent; changed["unauthorized"] = true;
    check(!ZStrictValidateEntitlements(profile,changed,"test.main"), "unauthorized extra right rejects");
    changed = ent; changed["com.apple.security.application-groups"][0] = "group.other";
    check(!ZStrictValidateEntitlements(profile,changed,"test.main"), "unauthorized app group rejects");
    changed = ent; changed["keychain-access-groups"][0] = "SYNTHETIC.*";
    check(!ZStrictValidateEntitlements(profile,changed,"test.main"), "wildcard desired rights reject");
    changed = ent; changed["keychain-access-groups"][0] = "SYNTHETIC.test.main";
    check(ZStrictValidateEntitlements(profile,changed,"test.main"), "fully qualified group under terminal wildcard grant");
    check(ZStrictLeafCertificateAllowed(profile,get(directory + "/A.der")), "actual synthetic DER leaf authorized");
    check(!ZStrictLeafCertificateAllowed(profile,get(directory + "/B.der")), "different actual DER leaf rejected");
    check(!ZStrictLeafCertificateAllowed(profile,""), "empty DER leaf rejected");
    changed=profile; changed["DeveloperCertificates"]=jvalue(jvalue::E_ARRAY);
    check(!ZStrictValidateEntitlements(changed,ent,"test.main"), "empty profile certificate grant rejects before keys");
    jbase64 encoder; changed["DeveloperCertificates"].push_back(string("data:")+encoder.encode(get(directory+"/A.der")));
    check(!ZStrictValidateEntitlements(changed,ent,"test.main") && !ZStrictLeafCertificateAllowed(changed,get(directory+"/A.der")), "string-lookalike certificate data cannot authorize selected leaf");
    changed=profile; changed["DeveloperCertificates"].push_back("malformed");
    check(!ZStrictValidateEntitlements(changed,ent,"test.main") && !ZStrictLeafCertificateAllowed(changed,get(directory+"/A.der")), "mixed malformed certificate grant rejects whole public metadata");
    ZSignAsset main, service, unauthorized, absent, legacy;
    check(main.Init(directory+"/A.pem",directory+"/A.key",directory+"/main.cms",directory+"/main.entitlements","",false,true,false,"test.main"), "real strict Init with synthetic PEM/CMS grants succeeds");
    check(service.Init(directory+"/A.pem",directory+"/A.key",directory+"/service.cms",directory+"/service.entitlements","",false,true,false,"test.main.NotificationService"), "real strict service Init succeeds");
    check(!unauthorized.Init(directory+"/A.pem",directory+"/A.key",directory+"/wrong.cms",directory+"/main.entitlements","",false,true,false,"test.main"), "real strict Init rejects selected PEM leaf absent from profile");
    check(!absent.Init("","",directory+"/missing.cms",directory+"/main.entitlements","",false,true,false,"test.main"), "strict Init missing profile fails before key loading");
    check(!absent.Init("","",directory+"/main.cms",directory+"/missing.entitlements","",false,true,false,"test.main"), "strict supplied entitlements cannot fall back");
    check(!absent.Init("","","","","",true,true,false,"test.main"), "profile-free adhoc cannot bypass strict Init");
    check(legacy.Init(directory+"/A.pem",directory+"/A.key",directory+"/wrong.cms",directory+"/main.entitlements","",false,true,false), "legacy Init behavior preserved separately");
    for (const string& name : {string("duplicate-app"),string("duplicate-team"),string("duplicate-encoded-app")}) {
        ZSignAsset ambiguous;
        check(!ambiguous.Init(directory+"/A.pem",directory+"/A.key",directory+"/"+name+".cms",directory+"/main.entitlements","",false,true,false,"test.main"), "actual strict Init rejects ambiguous CMS metadata before key load");
    }
    const string app = directory + "/Fixture.app";
    mkdir(app); mkdir(app+"/PlugIns"); mkdir(app+"/PlugIns/Service.appex"); mkdir(app+"/Frameworks"); mkdir(app+"/Frameworks/F.framework");
    info(app,"test.main","Main"); info(app+"/PlugIns/Service.appex","test.main.NotificationService","Service"); info(app+"/Frameworks/F.framework","test.framework","F");
    macho(app+"/Main",MH_EXECUTE); macho(app+"/PlugIns/Service.appex/Service",MH_EXECUTE); macho(app+"/Frameworks/F.framework/F",MH_DYLIB); macho(app+"/helper.dylib",MH_DYLIB);
    const set<string> ids{"test.main","test.main.NotificationService"};
    ZBundle missing, extra, valid;
    check(!missing.PrepareStrictSigning(app,{"test.main"}), "missing extension mapping fails graph preflight");
    check(!extra.PrepareStrictSigning(app,{"test.main","test.main.NotificationService","test.unused"}), "unused mapping fails graph preflight");
    check(valid.PrepareStrictSigning(app,ids), "actual strict graph preflight accepts main/service/framework");
    const string metadataFIFO=directory+"/metadata.fifo"; check(mkfifo(metadataFIFO.c_str(),0600)==0, "create owned metadata FIFO");
    check(boundedChild([&]() { string value; return !ZStrictReadFile(metadataFIFO,4096,value); }), "metadata FIFO rejects before blocking open/read");
    const string resourceFIFO=app+"/resource.fifo"; check(mkfifo(resourceFIFO.c_str(),0600)==0, "create owned bundle FIFO");
    check(boundedChild([&]() { ZBundle resource; return !resource.PrepareStrictSigning(app,ids); }), "strict preflight rejects FIFO resource before blocking magic probe");
    check(ZFile::RemoveFile(resourceFIFO.c_str()), "remove owned bundle FIFO");
    check(symlink(metadataFIFO.c_str(),(app+"/fifo-resource-link").c_str())==0, "create literal resource link to special target");
    check(boundedChild([&]() { ZBundle resource; return resource.PrepareStrictSigning(app,ids); }), "special resource link target is not opened during code probe");
    check(ZFile::RemoveFile((app+"/fifo-resource-link").c_str()), "remove owned special target link");
    const string serviceExe=app+"/PlugIns/Service.appex/Service"; const string serviceBytes=get(serviceExe);
    check(symlink("Service",(app+"/PlugIns/Service.appex/embedded.mobileprovision").c_str())==0, "create contained extension profile self-alias");
    ZBundle selfProfile; check(!selfProfile.PrepareStrictSigning(app,ids) && get(serviceExe)==serviceBytes, "extension output alias cannot overwrite admitted code");
    check(ZFile::RemoveFile((app+"/PlugIns/Service.appex/embedded.mobileprovision").c_str()), "remove owned profile self-alias");
    const string outside=directory+"/Outside.dylib"; macho(outside,MH_DYLIB); const string outsideBytes=get(outside);
    check(symlink(outside.c_str(),(app+"/outside.dylib").c_str())==0, "create owned external code symlink fixture");
    ZBundle external; check(!external.PrepareStrictSigning(app,ids) && get(outside)==outsideBytes, "external generic MachO symlink rejects without changing target");
    check(ZFile::RemoveFile((app+"/outside.dylib").c_str()), "remove owned external symlink");
    check(link(outside.c_str(),(app+"/outside-hardlink.dylib").c_str())==0, "create owned external hard-linked code fixture");
    ZBundle hardLinkedCode; check(!hardLinkedCode.PrepareStrictSigning(app,ids) && get(outside)==outsideBytes, "hard-linked code refuses mutation even with inside-root pathname");
    check(ZFile::RemoveFile((app+"/outside-hardlink.dylib").c_str()), "remove owned external code hardlink");
    string resolved;
    string canonicalDirectory,canonicalApp;
    check(ZStrictCanonicalPath(directory,canonicalDirectory) && ZStrictCanonicalPath(app,canonicalApp) && ZStrictContainedCode(canonicalDirectory,app+"/Main",resolved) && !ZStrictContainedCode(canonicalApp,outside,resolved) && !ZStrictContainedCode(canonicalApp,app+"/missing",resolved), "strict containment boundary and missing code guards");
    check(ZStrictContainedOutput(canonicalApp,app+"/embedded.mobileprovision",false) && ZStrictContainedOutput(canonicalApp,app+"/_CodeSignature/CodeResources",false), "fresh missing signing outputs remain valid inside root");
    const string outsideOutput=directory+"/OutsideOutput"; file(outsideOutput,"owned-output-marker");
    check(symlink(outsideOutput.c_str(),(app+"/embedded.mobileprovision").c_str())==0, "create owned external profile output alias");
    ZBundle externalProfile; check(!externalProfile.PrepareStrictSigning(app,ids) && get(outsideOutput)=="owned-output-marker", "external profile output rejects before key/mutation");
    check(ZFile::RemoveFile((app+"/embedded.mobileprovision").c_str()), "remove owned profile alias");
    check(link(outsideOutput.c_str(),(app+"/embedded.mobileprovision").c_str())==0, "create owned external hard-linked output fixture");
    ZBundle hardLinkedOutput; check(!hardLinkedOutput.PrepareStrictSigning(app,ids) && get(outsideOutput)=="owned-output-marker", "hard-linked signing output rejects before key/mutation");
    check(ZFile::RemoveFile((app+"/embedded.mobileprovision").c_str()), "remove owned external output hardlink");
    const string outsideSignature=directory+"/OutsideSignature"; mkdir(outsideSignature); file(outsideSignature+"/CodeResources","owned-resource-marker");
    check(symlink(outsideSignature.c_str(),(app+"/_CodeSignature").c_str())==0, "create owned external signature directory alias");
    ZBundle externalSignature; check(!externalSignature.PrepareStrictSigning(app,ids) && get(outsideSignature+"/CodeResources")=="owned-resource-marker", "external signature output parent rejects before key/mutation");
    check(ZFile::RemoveFile((app+"/_CodeSignature").c_str()), "remove owned signature alias");
    mkdir(app+"/_CodeSignature");
    check(symlink(outsideOutput.c_str(),(app+"/_CodeSignature/CodeResources").c_str())==0, "create owned external resource file alias");
    ZBundle externalResource; check(!externalResource.PrepareStrictSigning(app,ids) && get(outsideOutput)=="owned-output-marker", "external resource output rejects before key/mutation");
    check(ZFile::RemoveFile((app+"/_CodeSignature/CodeResources").c_str()), "remove owned resource alias");
    const string admittedInfo=get(app+"/Info.plist");
    check(symlink("../Info.plist",(app+"/_CodeSignature/CodeResources").c_str())==0, "create contained resource output self-alias");
    ZBundle selfResource; check(!selfResource.PrepareStrictSigning(app,ids) && get(app+"/Info.plist")==admittedInfo, "contained output self-alias cannot overwrite admitted metadata");
    check(ZFile::RemoveFile((app+"/_CodeSignature/CodeResources").c_str()), "remove owned resource self-alias");
    check(symlink("nonexistent",(app+"/_CodeSignature/CodeResources").c_str())==0 && !ZStrictContainedOutput(canonicalApp,app+"/_CodeSignature/CodeResources",false), "dangling output alias cannot masquerade as fresh missing path");
    check(ZFile::RemoveFile((app+"/_CodeSignature/CodeResources").c_str()), "remove owned dangling alias");
    const string framework=app+"/Frameworks/F.framework"; mkdir(framework+"/Versions"); mkdir(framework+"/Versions/A");
    check(rename((framework+"/F").c_str(),(framework+"/Versions/A/F").c_str())==0 && symlink("Versions/A/F",(framework+"/F").c_str())==0 && symlink("A",(framework+"/Versions/Current").c_str())==0, "create contained versioned framework executable alias");
    ZBundle versioned; check(versioned.PrepareStrictSigning(app,ids), "contained versioned framework code alias accepted");
    const string originalInfo = get(app+"/Info.plist");
    file(app+"/Info.plist",duplicatedInfo); ZBundle ambiguousInfo;
    check(!ambiguousInfo.PrepareStrictSigning(app,ids), "actual graph preflight rejects duplicated Info ID");
    file(app+"/Info.plist",get(directory+"/valid-info.binary")); ZBundle binaryInfo;
    check(binaryInfo.PrepareStrictSigning(app,ids), "actual graph preflight accepts binary Info");
    file(app+"/plain.txt","ordinary-resource-control");
    const string escapedExecutableInfo = xml("<dict><key>CFBundleIdentifier</key><string>test.main</string><key>CFBundleExecutable</key><string>M&#97;in</string><key>CFBundleDisplayName</key><string>SuperGram &#x1f43e;</string></dict>");
    file(app+"/Info.plist",escapedExecutableInfo);
    check(valid.PrepareStrictSigning(app,ids), "strict canonical graph refreshed for contained aliases");
    check(!valid.SetStrictSignAssets({{"test.main",&main},{"test.main.NotificationService",nullptr}}), "null/failed asset rejected");
    check(!valid.SetStrictSignAssets({{"test.main",&main},{"test.main.NotificationService",&main}}), "exact selected profile cannot be suffix matched");
    for (const string& name : {string("unsupported-zero"),string("unsupported-real"),string("unsupported-promotion"),string("unsupported-entity")}) {
        ZSignAsset rejected;
        check(!rejected.Init(directory+"/A.pem",directory+"/A.key",directory+"/"+name+".cms",directory+"/"+name+".entitlements","",false,true,false,"test.main"), "actual strict Init rejects incompatible signed-rights serialization before keys");
    }
    const string saved = service.m_strLeafCertificateData; service.m_strLeafCertificateData = "wrong";
    check(!valid.SetStrictSignAssets({{"test.main",&main},{"test.main.NotificationService",&service}}), "mapped leaf mismatch rejected"); service.m_strLeafCertificateData = saved;
    check(valid.SetStrictSignAssets({{"test.main.NotificationService",&service},{"test.main",&main}}), "reverse input order chooses same exact assets");
    signingCalls.clear();
    check(valid.SignFolder(&main,app,"","","",{},{},true,false,false,false), "actual SignNode routes with instrumented signer only");
    int mainCount=0, serviceCount=0, frameworkCount=0, helperCount=0;
    for (const auto& call : signingCalls) {
        if (call.first == app+"/Main") { ++mainCount; check(call.second == &main, "main node asset stable"); }
        else if (call.first == app+"/PlugIns/Service.appex/Service") { ++serviceCount; check(call.second == &service, "extension uses own asset"); }
        else if (call.first == app+"/Frameworks/F.framework/F") { ++frameworkCount; check(call.second == &main, "framework uses stable main asset"); }
        else if (call.first == app+"/helper.dylib") { ++helperCount; check(call.second == &main, "loose dylib uses stable main asset"); }
        else check(false,"unexpected signing dispatch");
    }
    check(mainCount==1 && serviceCount==1 && frameworkCount==1 && helperCount==1, "known bundle executables only signed by their node once");
    check(get(app+"/embedded.mobileprovision") == main.m_strProvData && get(app+"/PlugIns/Service.appex/embedded.mobileprovision") == service.m_strProvData, "own profiles installed before resource seal");
    jvalue resources;
    check(resources.read_plist(get(app+"/_CodeSignature/CodeResources")) && !resources["files"].has("Main") && !resources["files2"].has("Main"), "strict resource map omits decoded executable name consistently");
    jvalue frameworkResources;
    check(frameworkResources.read_plist(get(framework+"/_CodeSignature/CodeResources")) && frameworkResources["files2"]["Versions/Current"]["symlink"].as_string()=="A" && !frameworkResources["files"].has("Versions/Current"), "contained versioned framework directory link seals literal V2 target and is omitted from V1 without hashing a directory");
    check(resources["files2"]["Frameworks/F.framework/Versions/Current"]["symlink"].as_string()=="A" && resources["files2"]["helper.dylib"]["hash2"].is_data(), "parent link seal and ordinary resource hashes retain typed representation");
    const string legacyApp=directory+"/Legacy.app"; mkdir(legacyApp); info(legacyApp,"test.main","Main"); macho(legacyApp+"/Main",MH_EXECUTE); file(legacyApp+"/plain.txt","ordinary-resource-control");
    ZBundle legacyBundle; signingCalls.clear();
    check(legacyBundle.SignFolder(&main,legacyApp,"","","",{},{},true,false,false,false), "legacy default single-main bundle behavior remains available");
    jvalue legacyResources;
    check(legacyResources.read_plist(get(legacyApp+"/_CodeSignature/CodeResources")) && legacyResources["files2"]["plain.txt"]["hash2"].as_data()==resources["files2"]["plain.txt"]["hash2"].as_data(), "ordinary resource seal hashes agree with unchanged legacy path");
    file(app+"/Info.plist",originalInfo);
    for (const string& target : {string("data:QQ=="),string("date:2026-10-09T00:00:00Z")}) {
        check(symlink(target.c_str(),(framework+"/unsupported-resource-link").c_str())==0, "create owned promoted-string resource link");
        check(!valid.SignFolder(&main,app,"","","",{},{},true,false,false,false), "resource target string promotion fails closed before sealing/signing node");
        check(ZFile::RemoveFile((framework+"/unsupported-resource-link").c_str()), "remove owned unsupported resource link");
    }
    check(ZFile::RemoveFile((framework+"/F").c_str()) && symlink(outside.c_str(),(framework+"/F").c_str())==0, "change known framework alias after strict preflight");
    signingCalls.clear();
    check(!valid.SignFolder(&main,app,"","","",{},{},true,false,false,false) && get(outside)==outsideBytes, "changed external code alias rejects without writing outside staging");
    check(ZFile::RemoveFile((framework+"/F").c_str()) && symlink("Versions/A/F",(framework+"/F").c_str())==0, "restore contained owned alias");
    macho(app+"/unknown-helper",MH_EXECUTE); ZBundle unknown;
    check(!unknown.PrepareStrictSigning(app,ids), "unclassified MH_EXECUTE fails before signing");
    check(ZFile::RemoveFile((app+"/unknown-helper").c_str()), "remove owned unknown helper");
    info(app+"/PlugIns/Service.appex","test.main","Service"); ZBundle duplicate;
    check(!duplicate.PrepareStrictSigning(app,{"test.main"}), "duplicate bundle ID fails graph preflight");
    cout << "PASS: " << checks << " actual-source strict signer assertions; no binary signed" << endl;
}
'''

FAKE = r'''
#include "common.h"
#include "macho.h"
#include <fstream>
#include <cstdarg>
vector<pair<string, ZSignAsset*>> signingCalls;
ZMachO::ZMachO() { m_pBase=nullptr; m_sSize=0; m_bCSRealloced=false; }
ZMachO::~ZMachO() { FreeArchOes(); }
ZArchO::ZArchO() {}
uint32_t ZArchO::BO(uint32_t value) { return value; }
void ZMachO::FreeArchOes() { for (auto arch:m_arrArchOes) { delete arch->m_pHeader; delete arch; } m_arrArchOes.clear(); }
bool ZMachO::Init(const char* path) {
    FreeArchOes(); m_strFile=path; uint32_t header[8]; std::ifstream input(path,std::ios::binary);
    if (!input.read(reinterpret_cast<char*>(header),sizeof(header)) || header[0]!=MH_MAGIC_64) return false;
    auto arch=new ZArchO(); arch->m_pHeader=new mach_header(); arch->m_pHeader->filetype=header[3]; m_arrArchOes.push_back(arch); return true;
}
bool ZMachO::InitV(const char* format, ...) { char path[4096]; va_list args; va_start(args,format); vsnprintf(path,sizeof(path),format,args); va_end(args); return Init(path); }
bool ZMachO::Sign(ZSignAsset* asset,bool,string,string,string,const string&) { signingCalls.emplace_back(m_strFile,asset); return true; }
bool ZMachO::InjectDylib(bool,const char*) { return false; }
void ZMachO::RemoveDylibs(const set<string>&) {}
'''
FAKE += block((SRC/'archo.cpp').read_text(), 'bool ZArchO::IsExecute()')
FAKE += block((SRC/'macho.cpp').read_text(), 'bool ZMachO::IsExecute() const')
FAKE += block((SRC/'macho.cpp').read_text(), 'bool ZMachO::HasExecute() const')

with tempfile.TemporaryDirectory(prefix='supergram-zsign-strict-') as temporary:
    fixture = Path(temporary)
    for label in ['A','B']:
        run(['openssl','req','-new','-x509','-newkey','rsa:2048','-nodes','-subj',f'/CN=SuperGram Synthetic {label}', '-days','1','-keyout',str(fixture/f'{label}.key'),'-out',str(fixture/f'{label}.pem')])
        run(['openssl','x509','-in',str(fixture/f'{label}.pem'),'-outform','DER','-out',str(fixture/f'{label}.der')])
    def entitlement(identifier):
        return {'application-identifier':f'SYNTHETIC.{identifier}', 'com.apple.developer.team-identifier':'SYNTHETIC','get-task-allow':False,
                'com.apple.security.application-groups':['group.synthetic'], 'keychain-access-groups':[f'SYNTHETIC.{identifier}']}
    for name, identifier, certificate in [('main','test.main','A'),('service','test.main.NotificationService','A'),('wrong','test.main','B')]:
        desired = entitlement(identifier)
        grant = dict(desired, **{'keychain-access-groups':['SYNTHETIC.*']})
        profile = {'TeamIdentifier':['SYNTHETIC'],'Entitlements':grant,'DeveloperCertificates':[(fixture/f'{certificate}.der').read_bytes()]}
        (fixture/f'{name}.profile.plist').write_bytes(plistlib.dumps(profile))
        if name != 'wrong':
            (fixture/f'{name}.entitlements').write_bytes(plistlib.dumps(desired))
        run(['openssl','cms','-sign','-binary','-nodetach','-noattr','-in',str(fixture/f'{name}.profile.plist'),'-signer',str(fixture/'A.pem'),'-inkey',str(fixture/'A.key'),'-outform','DER','-out',str(fixture/f'{name}.cms')])
    for name, value in [('unsupported-zero',0),('unsupported-real',1e300),('unsupported-promotion','data:QQ=='),('unsupported-entity','A&B')]:
        desired=entitlement('test.main'); desired['fixture-value']=value
        profile={'TeamIdentifier':['SYNTHETIC'],'Entitlements':desired,'DeveloperCertificates':[(fixture/'A.der').read_bytes()]}
        (fixture/f'{name}.profile.plist').write_bytes(plistlib.dumps(profile))
        (fixture/f'{name}.entitlements').write_bytes(plistlib.dumps(desired))
        run(['openssl','cms','-sign','-binary','-nodetach','-noattr','-in',str(fixture/f'{name}.profile.plist'),'-signer',str(fixture/'A.pem'),'-inkey',str(fixture/'A.key'),'-outform','DER','-out',str(fixture/f'{name}.cms')])
    def binary_string(value, unicode=False):
        data = value.encode('utf-16be') if unicode else value.encode('utf-8')
        length = len(data)//2 if unicode else len(data)
        prefix = 0x60 if unicode else 0x50
        size = 1 if length < 256 else 2
        return (bytes([prefix | length]) if length < 15 else bytes([prefix | 15,0x10 if size==1 else 0x11])+length.to_bytes(size,'big')) + data
    def binary_objects(objects, ref_size=1):
        body = b'bplist00'; offsets=[]
        for obj in objects: offsets.append(len(body)); body += obj
        table=len(body)
        offset_size = 1 if max(offsets) < 256 else 2
        body += b''.join(offset.to_bytes(offset_size,'big') for offset in offsets)
        return body + b'\0'*6 + bytes([offset_size,ref_size]) + struct.pack('>QQQ',len(objects),0,table)
    def binary_pairs(pairs):
        objects = [bytes([0xd0 | len(pairs)]) + bytes(range(1,1+len(pairs))) + bytes(range(1+len(pairs),1+2*len(pairs)))]
        objects += [binary_string(key, unicode) for key,value,unicode in pairs]
        objects += [binary_string(value) for key,value,unicode in pairs]
        return binary_objects(objects)
    def shared_arrays(levels, copies, ref_size=1):
        ref=lambda number: number.to_bytes(ref_size,'big')
        objects=[b'\xd1'+ref(1)+ref(2),binary_string('array')]
        objects += [bytes([0xa0 | copies])+ref(index+1)*copies for index in range(2,2+levels)]
        objects += [binary_string('x')]
        return binary_objects(objects,ref_size)
    (fixture/'shared-small.binary').write_bytes(shared_arrays(9,2))
    (fixture/'shared-medium.binary').write_bytes(shared_arrays(14,2))
    (fixture/'shared-large.binary').write_bytes(shared_arrays(16,2))
    (fixture/'cyclic.binary').write_bytes(binary_objects([b'\xd1\x01\x02',binary_string('array'),b'\xa1\x02']))
    (fixture/'deep.binary').write_bytes(shared_arrays(260,1,2))
    def shared_leaf(leaf, copies):
        array=b'\xaf\x11'+copies.to_bytes(2,'big')+b'\x03'*copies
        return binary_objects([b'\xd1\x01\x02',binary_string('array'),array,leaf])
    data_leaf=b'\x4f\x11'+(4096).to_bytes(2,'big')+b'A'*4096
    (fixture/'shared-data-wide.binary').write_bytes(shared_leaf(data_leaf,4096))
    (fixture/'shared-data-control.binary').write_bytes(shared_leaf(data_leaf,2048))
    (fixture/'shared-data-near-limit.binary').write_bytes(shared_leaf(data_leaf,4095))
    (fixture/'shared-ascii-wide.binary').write_bytes(shared_leaf(binary_string('A'*4096),4096))
    (fixture/'shared-unicode-wide.binary').write_bytes(shared_leaf(binary_string('ࠀ'*2048,True),2731))
    for name, value in [('real-nan',b'\x23'+struct.pack('>d',float('nan'))),('real-infinity',b'\x23'+struct.pack('>d',float('inf'))),('float-nan',b'\x22'+struct.pack('>f',float('nan'))),
                        ('date-nan',b'\x33'+struct.pack('>d',float('nan'))),('date-infinity',b'\x33'+struct.pack('>d',float('inf'))),('date-huge',b'\x33'+struct.pack('>d',1e300)),('date-negative-huge',b'\x33'+struct.pack('>d',-1e300)),
                        ('date-zero',b'\x33'+struct.pack('>d',0)),('null-array',b'\xa1\x03'),('uid',b'\x80\x01'),('unknown-null',b'\x0f')]:
        objects=[b'\xd1\x01\x02',binary_string('date' if name.startswith('date-') else 'value'),value]
        if name=='null-array': objects.append(b'\x00')
        (fixture/f'{name}.binary').write_bytes(binary_objects(objects))
    known_date={'date':datetime.datetime(2026,10,9)}
    (fixture/'known-date.binary').write_bytes(plistlib.dumps(known_date,fmt=plistlib.FMT_BINARY))
    (fixture/'known-date.xml').write_bytes(plistlib.dumps(known_date))
    (fixture/'valid-info.binary').write_bytes(plistlib.dumps({'CFBundleIdentifier':'test.main','CFBundleExecutable':'Main','CFBundleVersion':'1'},fmt=plistlib.FMT_BINARY))
    (fixture/'duplicate-info.binary').write_bytes(binary_pairs([('CFBundleIdentifier','test.main',False),('CFBundleIdentifier','test.other',False)]))
    (fixture/'unicode-duplicate-info.binary').write_bytes(binary_pairs([('CFBundleIdentifier','test.main',False),('CFBundleIdentifier','test.other',True)]))
    (fixture/'nul-info.binary').write_bytes(binary_pairs([('CFBundleIdentifier','test.main\0other',False)]))
    (fixture/'emoji-info.binary').write_bytes(plistlib.dumps({'CFBundleIdentifier':'test.main','CFBundleDisplayName':'SuperGram 🐾'},fmt=plistlib.FMT_BINARY))
    for name, units in [('unicode-high',[0xd83d]),('unicode-low',[0xdc3e]),('unicode-high-ascii',[0xd83d,0x41]),('unicode-reversed',[0xdc3e,0xd83d]),('unicode-nul',[0])]:
        value=bytes([0x60 | len(units)])+b''.join(struct.pack('>H',unit) for unit in units)
        (fixture/f'{name}.binary').write_bytes(binary_objects([b'\xd1\x01\x02',binary_string('value'),value]))
    paired_key=b'\x62\xd8\x3d\xdc\x3e'
    utf8_key=b'\x74'+bytes.fromhex('f09f90be')
    (fixture/'emoji-duplicate.binary').write_bytes(binary_objects([b'\xd2\x01\x02\x03\x04',paired_key,utf8_key,b'\x51a',b'\x51b']))
    profile_text=(fixture/'main.profile.plist').read_text()
    app_key='<key>application-identifier</key>'
    app_pair=app_key+'\n\t\t<string>SYNTHETIC.test.main</string>'
    assert app_pair in profile_text
    duplicate_app=profile_text.replace(app_pair,app_pair+'\n\t\t'+app_pair,1)
    duplicate_encoded_app=profile_text.replace(app_pair,app_pair+'\n\t\t'+app_pair.replace(app_key,'<key>&#97;pplication-identifier</key>'),1)
    duplicate_team=profile_text.replace('\n</dict>\n</plist>', '\n<key>TeamIdentifier</key><array><string>SYNTHETIC</string></array>\n</dict>\n</plist>',1)
    service_profile_text=(fixture/'service.profile.plist').read_text()
    service_app_pair=app_key+'\n\t\t<string>SYNTHETIC.test.main.NotificationService</string>'
    assert service_app_pair in service_profile_text
    duplicate_service=service_profile_text.replace(service_app_pair,service_app_pair+'\n\t\t'+service_app_pair,1)
    for name, content in [('duplicate-app',duplicate_app),('duplicate-team',duplicate_team),('duplicate-encoded-app',duplicate_encoded_app),('duplicate-service-app',duplicate_service)]:
        (fixture/f'{name}.profile.plist').write_text(content)
        run(['openssl','cms','-sign','-binary','-nodetach','-noattr','-in',str(fixture/f'{name}.profile.plist'),'-signer',str(fixture/'A.pem'),'-inkey',str(fixture/'A.key'),'-outform','DER','-out',str(fixture/f'{name}.cms')])
    (fixture/'main.cpp').write_text(TEST)
    (fixture/'fake_macho.cpp').write_text(FAKE)
    flags = run(['pkg-config','--cflags','--libs','openssl'],text=True).stdout.split()
    command = ['c++','-std=c++11','-O0','-I'+str(SRC),'-I'+str(SRC/'common'),str(fixture/'main.cpp'),str(fixture/'fake_macho.cpp'),str(SRC/'bundle.cpp'),str(SRC/'openssl.cpp'),str(SRC/'signing.cpp')]
    command += [str(p) for p in sorted((SRC/'common').glob('*.cpp')) if p.name != 'archive.cpp']
    if args.sanitize: command += ['-fsanitize=address','-g']
    command += flags + ['-o',str(fixture/'test')]
    result=run(command,text=True)
    result=run([str(fixture/'test'),str(fixture)],text=True)
    print(result.stdout)
    if args.candidate:
        candidate = args.candidate.resolve()
        app=fixture/'Cli.app'; app.mkdir()
        (app/'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'test.main','CFBundleExecutable':'Main','CFBundleVersion':'1'}))
        (app/'Main').write_bytes(struct.pack('<8I',0xfeedfacf,0,0,2,0,0,0,0))
        manifest=fixture/'map.json'
        for entries in [[], [{'bundle_id':'test.main','profile_path':'missing','entitlements_path':'missing'}],
                        [{'bundle_id':'test.unused','profile_path':'missing','entitlements_path':'missing'}]]:
            manifest.write_text(json.dumps(entries))
            before = hashlib.sha256((app/'Main').read_bytes()).hexdigest()
            result=subprocess.run([str(candidate),'--bundle-signing-map',str(manifest),str(app)],capture_output=True,text=True,cwd=fixture)
            assert result.returncode > 0 and hashlib.sha256((app/'Main').read_bytes()).hexdigest()==before
            assert not (app/'embedded.mobileprovision').exists()
        service=app/'PlugIns'/'Service.appex'; service.mkdir(parents=True)
        (service/'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'test.main.NotificationService','CFBundleExecutable':'Service','CFBundleVersion':'1'}))
        (service/'Service').write_bytes(struct.pack('<8I',0xfeedfacf,0,0,2,0,0,0,0))
        manifest.write_text(json.dumps([{'bundle_id':'test.main','profile_path':str(fixture/'main.cms'),'entitlements_path':str(fixture/'main.entitlements')},
                                        {'bundle_id':'test.main.NotificationService','profile_path':str(fixture/'service.cms'),'entitlements_path':str(fixture/'service.entitlements')}]))
        result=subprocess.run([str(candidate),'--bundle-signing-map',str(manifest),str(app)],capture_output=True,text=True,cwd=fixture)
        assert result.returncode > 0 and 'Strict bundle asset initialization failed' in result.stdout+result.stderr
        assert not (app/'embedded.mobileprovision').exists() and not (service/'embedded.mobileprovision').exists()
        original_entries=json.loads(manifest.read_text())
        def unchanged():
            assert not (app/'embedded.mobileprovision').exists() and not (service/'embedded.mobileprovision').exists()
            assert not (app/'_CodeSignature').exists() and not (service/'_CodeSignature').exists()
            assert (app/'Main').read_bytes()==struct.pack('<8I',0xfeedfacf,0,0,2,0,0,0,0)
            assert (service/'Service').read_bytes()==struct.pack('<8I',0xfeedfacf,0,0,2,0,0,0,0)
        for name, index in [('duplicate-app',0),('duplicate-team',0),('duplicate-encoded-app',0),('duplicate-service-app',1)]:
            entries=[dict(record) for record in original_entries]
            entries[index]['profile_path']=str(fixture/f'{name}.cms')
            manifest.write_text(json.dumps(entries))
            result=subprocess.run([str(candidate),'--bundle-signing-map',str(manifest),str(app)],capture_output=True,text=True,cwd=fixture)
            assert result.returncode > 0 and 'Strict bundle metadata validation failed' in result.stdout+result.stderr
            assert 'Strict bundle asset initialization failed' not in result.stdout+result.stderr
            unchanged()
        for name in ['unsupported-zero','unsupported-real','unsupported-promotion','unsupported-entity']:
            entries=[dict(record) for record in original_entries]
            entries[0]['profile_path']=str(fixture/f'{name}.cms')
            entries[0]['entitlements_path']=str(fixture/f'{name}.entitlements')
            manifest.write_text(json.dumps(entries))
            result=subprocess.run([str(candidate),'--bundle-signing-map',str(manifest),str(app)],capture_output=True,text=True,cwd=fixture)
            assert result.returncode > 0 and 'unsupported XML/DER entitlement serialization' in result.stdout+result.stderr
            assert 'Strict bundle asset initialization failed' not in result.stdout+result.stderr
            unchanged()
        manifest.write_text(json.dumps(original_entries))
        metadata_fifo=fixture/'CliMetadata.fifo'; os.mkfifo(metadata_fifo)
        entries=[dict(record) for record in original_entries]; entries[0]['profile_path']=str(metadata_fifo)
        manifest.write_text(json.dumps(entries))
        result=subprocess.run([str(candidate),'--bundle-signing-map',str(manifest),str(app)],capture_output=True,text=True,cwd=fixture,timeout=3)
        assert result.returncode > 0 and 'Strict bundle metadata validation failed' in result.stdout+result.stderr
        unchanged(); manifest.write_text(json.dumps(original_entries))
        os.mkfifo(app/'resource.fifo')
        result=subprocess.run([str(candidate),'--bundle-signing-map',str(manifest),str(app)],capture_output=True,text=True,cwd=fixture,timeout=3)
        assert result.returncode > 0 and 'Strict bundle asset initialization failed' not in result.stdout+result.stderr
        unchanged(); (app/'resource.fifo').unlink()
        outside=fixture/'CliOutside.dylib'; outside.write_bytes(struct.pack('<8I',0xfeedfacf,0,0,6,0,0,0,0))
        outside_bytes=outside.read_bytes()
        (app/'external.dylib').symlink_to(outside)
        result=subprocess.run([str(candidate),'--bundle-signing-map',str(manifest),str(app)],capture_output=True,text=True,cwd=fixture)
        assert result.returncode > 0 and 'Strict bundle asset initialization failed' not in result.stdout+result.stderr and outside.read_bytes()==outside_bytes
        unchanged(); (app/'external.dylib').unlink()
        os.link(outside,app/'external-hardlink.dylib')
        result=subprocess.run([str(candidate),'--bundle-signing-map',str(manifest),str(app)],capture_output=True,text=True,cwd=fixture)
        assert result.returncode > 0 and 'Strict bundle asset initialization failed' not in result.stdout+result.stderr and outside.read_bytes()==outside_bytes
        unchanged(); (app/'external-hardlink.dylib').unlink()
        outside_output=fixture/'CliOutsideOutput'; outside_output.write_text('owned-marker')
        (app/'embedded.mobileprovision').symlink_to(outside_output)
        result=subprocess.run([str(candidate),'--bundle-signing-map',str(manifest),str(app)],capture_output=True,text=True,cwd=fixture)
        assert result.returncode > 0 and 'Strict bundle asset initialization failed' not in result.stdout+result.stderr and outside_output.read_text()=='owned-marker'
        assert (app/'embedded.mobileprovision').is_symlink()
        (app/'embedded.mobileprovision').unlink(); unchanged()
        os.link(outside_output,app/'embedded.mobileprovision')
        result=subprocess.run([str(candidate),'--bundle-signing-map',str(manifest),str(app)],capture_output=True,text=True,cwd=fixture)
        assert result.returncode > 0 and 'Strict bundle asset initialization failed' not in result.stdout+result.stderr and outside_output.read_text()=='owned-marker'
        (app/'embedded.mobileprovision').unlink(); unchanged()
        outside_signature=fixture/'CliOutsideSignature'; outside_signature.mkdir(); (outside_signature/'CodeResources').write_text('owned-signature-marker')
        (app/'_CodeSignature').symlink_to(outside_signature,target_is_directory=True)
        result=subprocess.run([str(candidate),'--bundle-signing-map',str(manifest),str(app)],capture_output=True,text=True,cwd=fixture)
        assert result.returncode > 0 and 'Strict bundle asset initialization failed' not in result.stdout+result.stderr and (outside_signature/'CodeResources').read_text()=='owned-signature-marker'
        assert (app/'_CodeSignature').is_symlink()
        (app/'_CodeSignature').unlink(); unchanged()
        original_info=(app/'Info.plist').read_bytes()
        for ambiguous in [(fixture/'duplicate-info.binary').read_bytes(),(fixture/'unicode-duplicate-info.binary').read_bytes(),original_info.replace(b'<key>CFBundleIdentifier</key>',b'<key>CFBundleIdentifier</key><string>test.other</string><key>CFBundleIdentifier</key>',1)]:
            (app/'Info.plist').write_bytes(ambiguous)
            result=subprocess.run([str(candidate),'--bundle-signing-map',str(manifest),str(app)],capture_output=True,text=True,cwd=fixture)
            assert result.returncode > 0 and 'Strict bundle asset initialization failed' not in result.stdout+result.stderr
            unchanged()
        (app/'Info.plist').write_bytes(original_info)
        manifest.write_text('[]')
        marker='synthetic-regression-marker'
        result=subprocess.run([str(candidate),'-d','-p',marker,'--bundle-signing-map',str(manifest),str(app)],capture_output=True,text=True,cwd=fixture)
        assert result.returncode > 0 and marker not in result.stdout+result.stderr
        print('PASS: 23 candidate fail-before-sign/init/metadata/DER/containment/FIFO/log-redaction routes; no key supplied or binary signed')
