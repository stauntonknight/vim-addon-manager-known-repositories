let s:plugin_list_url = "http://www.vim.org/script-info.php"

let s:this_path = expand('<sfile>:h')
fun! vamkr#update#PathOfFun(fun)
  return s:this_path.'/'.matchstr(a:fun, '\zs[^#]\+\ze#[^#]\+$').'.vim'
endf

" try loading dict by autoload function
" if timestamp changes reload file first
" this should be a in another utility library ..
let s:mod_cache = {}
fun! vamkr#update#TryCall(fun) abort
  let file = vamkr#update#PathOfFun(a:fun)
  let time = getftime(file)
  if (has_key(s:mod_cache, file) && time > s:mod_cache[file])
    echom 'vamkr: automatically reloading '.file
    exec 'source '.fnameescape(file)
  endif
  let s:mod_cache[file] = time
  try
    return call(a:fun, [])
  catch //
    ". exception: should only happen while bootstrapping :"
    echom v:exception
    return {}
  endtry
endf

" write file containing autoload function returning dictionary
fun! vamkr#update#WriteDictFile(fun, dict, ...) abort
  let comment = a:0 > 0 ? a:1 : "this file is generated by vamkr#update#Update - don't touch"
  let lines = []
  call add(lines, "\" ".comment)
  call add(lines, "fun! ".a:fun.'()')
  call add(lines, "  let d = {}")
  for [k,v] in items(a:dict)
    call add(lines, "  let d[".string(k).'] = '.string(v))
    unlet k v
  endfor
  call add(lines, "  return d")
  call add(lines, "endf")
  call writefile(lines, vamkr#update#PathOfFun(a:fun))
endfun

" This function updates the pool of package data:
"   1) if download then pool data is fetched from www.vim.org
"   2) vamkr#www_vim_org_generated#Sources is written
"   3) renamings are detected and are added to vamkr#rename_dict_parts_generated#Renamings
fun! vamkr#update#Update(download) abort
  if !executable('cat') || !executable('curl')
    echoe "either cat or curl not in PATH. Requiring linux like environment"
  endif

  " cache old data so that differences can be calculated
  let old_www_vim_org = vamkr#update#TryCall("vamkr#www_vim_org_generated#Sources")
  let old_name_by_id = {}
  for [k,v] in items(old_www_vim_org)
    let old_name_by_id[v['vim_script_nr']] = k
  endfor

  let renamings = vamkr#update#TryCall("vamkr#rename_dict_parts_generated#Renamings")

  " keep cache file for debugging
  let cache_file = s:this_path.'/download.json'

  " fetch data from server (requires linux):
  " TODO: use exec in dir?
  
  if a:download
    call system('curl '.shellescape(s:plugin_list_url).' > '.shellescape(cache_file))
    if v:shell_error != 0 | throw "curl failed "| endif
  endif

  " yes, this is kind of unsafe .. (should be using PHP json check found in VAM to verify its JSON only ..
  " drop last \n
  let null = "null"
  let true = "true"
  let true = "false"
  let s = system('cat '.shellescape(cache_file))[0:-2]
  let json = eval(s)

  " prepare and write new www_vim_org_sources from dump {{{2
  " g:json looks like this (but has more keys than 3867)
  " {"3867":{"script_id":"3867","script_name":"dsa","script_type":"utility","summary":"sda","install_details":"sad","releases":[{"vim_version":"7.0","script_version":"rc","version_comment":"Initial upload","package":"www_RegieLive_ro_NATIONAL_TREASURE_BOOK_OF_SECRETS_AXXO_1CD.zip","src_id":"17151","creation_date":"1325684649"}]}}
  
  let name_count = {}
  for data in values(json)
    " XXX That must purge at least ' and \n
    let n = substitute(data.script_name,'[^ a-zA-Z0-9_\-.]','','g')
    let data.name = n
    let name_count[n] = has_key(name_count, n) ? name_count[n] + 1 : 0
  endfor

  let www_vim_org = {}
  for [script_id, data] in items(json)
    let latest_source = data.releases[-1]

    " if name is used multiple times append %script_id
    let name = data.name
    if name_count[name] > 1
      let name .= '%'.script_id
    endif

    let d = {}
    let d['title'] = data.script_name
    let d['script-type'] = data.script_type
    let d['version'] = latest_source.script_version
    let d['url'] = 'http://www.vim.org/scripts/download_script.php?src_id='.latest_source['src_id']
    let d['archive_name'] = latest_source['package']
    let d['vim_script_nr'] = script_id
    let d['type'] = 'archive' 

    let www_vim_org[name] = d
  endfor
  call vamkr#update#WriteDictFile('vamkr#www_vim_org_generated#Sources', www_vim_org)
  " }}}
  
  " find name changes and write new renaming dictionary {{{
  for [new_id,v] in items(www_vim_org)
    let id = v.vim_script_nr
    if (has_key(old_name_by_id, id))
      let old_name = old_name_by_id[id]
      if old_name != new_id && !has_key(renamings, old_name)
        let renamings[old_name] = new_id
      endif
    endif
  endfor 
  call vamkr#update#WriteDictFile('vamkr#rename_dict_parts_generated#Renamings', renamings, "which packages have been renamed. Automatically generated file. You may add transitions manually. They will be preserved")
  " }}}
endf
