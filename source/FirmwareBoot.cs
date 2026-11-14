// UEFI boot-option construction and removal.
// This source was not validated on a Windows UEFI machine. Do not run on a real machine.
using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

internal static class FirmwareBoot
{
    const string GlobalGuid = "{8BE4DF61-93CA-11D2-AA0D-00E098032B8C}";
    const uint Attr = 7; // NON_VOLATILE | BOOTSERVICE_ACCESS | RUNTIME_ACCESS
    const uint TokenAdjustPrivileges = 0x20, TokenQuery = 0x08, SePrivilegeEnabled = 2;
    [StructLayout(LayoutKind.Sequential)] struct Luid { public uint Low; public int High; }
    [StructLayout(LayoutKind.Sequential)] struct TokenPrivileges { public uint Count; public Luid Luid; public uint Attributes; }
    [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool CloseHandle(IntPtr handle);
    [DllImport("advapi32.dll", SetLastError=true)] static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
    [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool LookupPrivilegeValue(string system, string name, out Luid luid);
    [DllImport("advapi32.dll", SetLastError=true)] static extern bool AdjustTokenPrivileges(IntPtr token, bool disable, ref TokenPrivileges state, uint size, IntPtr previous, IntPtr returned);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern uint GetFirmwareEnvironmentVariableEx(string name, string guid, byte[] buffer, uint size, out uint attributes);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool SetFirmwareEnvironmentVariableEx(string name, string guid, byte[] buffer, uint size, uint attributes);
    static Win32Exception Error() { return new Win32Exception(Marshal.GetLastWin32Error()); }
    static void EnablePrivilege()
    {
        IntPtr token;
        if (!OpenProcessToken(GetCurrentProcess(), TokenAdjustPrivileges | TokenQuery, out token)) throw Error();
        try {
            Luid luid; if (!LookupPrivilegeValue(null, "SeSystemEnvironmentPrivilege", out luid)) throw Error();
            var privileges = new TokenPrivileges { Count = 1, Luid = luid, Attributes = SePrivilegeEnabled };
            if (!AdjustTokenPrivileges(token, false, ref privileges, 0, IntPtr.Zero, IntPtr.Zero)) throw Error();
            if (Marshal.GetLastWin32Error() != 0) throw Error();
        } finally { CloseHandle(token); }
    }
    static byte[] Read(string name, out uint attrs)
    {
        byte[] data = new byte[65536];
        uint n = GetFirmwareEnvironmentVariableEx(name, GlobalGuid, data, (uint)data.Length, out attrs);
        if (n == 0) { int code = Marshal.GetLastWin32Error(); if (code == 203) return null; throw new Win32Exception(code); }
        Array.Resize(ref data, (int)n); return data;
    }
    // PartitionStart and PartitionSize are in logical blocks, not bytes.
    internal static byte[] BuildLoadOption(Guid partitionGuid, uint partitionNumber, ulong partitionStart, ulong partitionSize, string path, string description)
    {
        if (partitionGuid == Guid.Empty || partitionNumber == 0 || partitionSize == 0 || !path.StartsWith("\\")) throw new ArgumentException("Invalid partition or EFI path.");
        byte[] filePath = Encoding.Unicode.GetBytes(path + "\0");
        if (filePath.Length > ushort.MaxValue - 50) throw new ArgumentException("Path too long.");
        using (var stream = new MemoryStream()) using (var w = new BinaryWriter(stream, Encoding.Unicode)) {
            w.Write((uint)1); w.Write((ushort)(42 + 4 + filePath.Length + 4)); w.Write(Encoding.Unicode.GetBytes(description + "\0"));
            w.Write((byte)4); w.Write((byte)1); w.Write((ushort)42); w.Write(partitionNumber); w.Write(partitionStart); w.Write(partitionSize); w.Write(partitionGuid.ToByteArray()); w.Write((byte)2); w.Write((byte)2);
            w.Write((byte)4); w.Write((byte)4); w.Write((ushort)(4 + filePath.Length)); w.Write(filePath);
            w.Write((byte)0x7f); w.Write((byte)0xff); w.Write((ushort)4); return stream.ToArray();
        }
    }
    // Put the new recovery entry first and preserve the order of all existing entries.
    // Caller must confirm operations and verify the Windows entry before calling.
    internal static ushort Register(byte[] option)
    {
        EnablePrivilege(); uint oldAttrs; byte[] order = Read("BootOrder", out oldAttrs);
        if (order == null || order.Length == 0 || (order.Length & 1) != 0) throw new InvalidOperationException("BootOrder absent or invalid; refusing to change firmware.");
        int selected = -1;
        for (int i = 0; i <= 65535; i++) { uint ignored; if (Read("Boot" + i.ToString("X4"), out ignored) == null) { selected = i; break; } }
        if (selected < 0) throw new InvalidOperationException("No free firmware boot slot.");
        string name = "Boot" + selected.ToString("X4");
        if (!SetFirmwareEnvironmentVariableEx(name, GlobalGuid, option, (uint)option.Length, Attr)) throw Error();
        byte[] updated = new byte[order.Length + 2]; updated[0] = (byte)selected; updated[1] = (byte)(selected >> 8); Buffer.BlockCopy(order, 0, updated, 2, order.Length);
        if (!SetFirmwareEnvironmentVariableEx("BootOrder", GlobalGuid, updated, (uint)updated.Length, oldAttrs)) {
            int error = Marshal.GetLastWin32Error();
            SetFirmwareEnvironmentVariableEx(name, GlobalGuid, null, 0, Attr);
            throw new Win32Exception(error);
        }
        // Read back the actual firmware order; firmware may reject or rewrite it.
        uint checkedAttrs; byte[] actual = Read("BootOrder", out checkedAttrs);
        if (actual == null || actual.Length < 2 || actual[0] != (byte)selected || actual[1] != (byte)(selected >> 8))
            throw new InvalidOperationException("Firmware did not keep the recovery entry first. Check firmware boot order; the new entry may still exist.");
        return (ushort)selected;
    }
    // Remove only EFI entries whose hard-drive GUID and file path both match.
    internal static void RemoveRecoveryEntries(Guid partitionGuid)
    {
        EnablePrivilege();
        uint orderAttrs; byte[] order = Read("BootOrder", out orderAttrs);
        if (order == null || order.Length < 2 || (order.Length & 1) != 0) throw new InvalidOperationException("Invalid BootOrder.");
        var matches = new System.Collections.Generic.List<int>();
        for (int i = 0; i <= 65535; i++) {
            uint attrs; byte[] data = Read("Boot" + i.ToString("X4"), out attrs);
            if (data == null || data.Length < 10) continue;
            int pathLength = BitConverter.ToUInt16(data, 4), pos = 6;
            while (pos + 1 < data.Length && (data[pos] != 0 || data[pos + 1] != 0)) pos += 2;
            pos += 2;
            if (pos > data.Length || pathLength > data.Length - pos) continue;
            int end = pos + pathLength; bool guidMatches = false, ended = false;
            var path = new StringBuilder();
            while (pos + 4 <= end) {
                int type=data[pos], sub=data[pos+1], len=BitConverter.ToUInt16(data,pos+2);
                if (len < 4 || len > end-pos) break;
                if (type == 4 && sub == 1 && len == 42 && data[pos+41] == 2) {
                    byte[] id=new byte[16]; Buffer.BlockCopy(data,pos+24,id,0,16);
                    if (new Guid(id) == partitionGuid) guidMatches=true;
                }
                if (type == 4 && sub == 4 && len >= 6 && (len & 1) == 0) {
                    string segment=Encoding.Unicode.GetString(data,pos+4,len-4).TrimEnd('\0');
                    if (path.Length > 0 && path[path.Length-1] != '\\' && !segment.StartsWith("\\")) path.Append('\\');
                    path.Append(segment);
                }
                pos += len;
                if (type == 0x7f && sub == 0xff && len == 4) { ended=true; break; }
            }
            if (ended && pos == end && guidMatches && String.Equals(path.ToString(), @"\EFI\clonezilla\grubx64.efi", StringComparison.OrdinalIgnoreCase)) matches.Add(i);
        }
        if (matches.Count == 0) throw new InvalidOperationException("No matching firmware entry found.");
        uint nextAttrs; byte[] next=Read("BootNext",out nextAttrs);
        if (next != null && (next.Length != 2 || matches.Contains(BitConverter.ToUInt16(next,0)))) throw new InvalidOperationException("BootNext references a recovery entry or is invalid.");
        var updated=new System.Collections.Generic.List<byte>();
        for(int i=0;i<order.Length;i+=2) if(!matches.Contains(BitConverter.ToUInt16(order,i))) { updated.Add(order[i]); updated.Add(order[i+1]); }
        if(updated.Count == 0) throw new InvalidOperationException("Refusing to leave BootOrder empty.");
        byte[] check=Read("BootOrder",out orderAttrs);
        if(check == null || check.Length != order.Length) throw new InvalidOperationException("BootOrder changed.");
        for(int i=0;i<order.Length;i++) if(order[i]!=check[i]) throw new InvalidOperationException("BootOrder changed.");
        byte[] replacement=updated.ToArray();
        if(!SetFirmwareEnvironmentVariableEx("BootOrder",GlobalGuid,replacement,(uint)replacement.Length,orderAttrs)) throw Error();
        uint actualAttrs; byte[] actual=Read("BootOrder",out actualAttrs);
        if(actual==null || actual.Length!=replacement.Length) throw new InvalidOperationException("BootOrder verification failed.");
        for(int i=0;i<actual.Length;i++) if(actual[i]!=replacement[i]) throw new InvalidOperationException("BootOrder verification failed.");
        foreach(int id in matches) if(!SetFirmwareEnvironmentVariableEx("Boot"+id.ToString("X4"),GlobalGuid,null,0,Attr)) throw Error();
    }

}
