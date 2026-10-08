unit PascalJsonMapper.NamingTests;

{$mode delphi}{$H+}

{ GENERATED FILE — produced by tools/gen_fpc_mirror.py from
  tests/Unit/PascalJsonMapper.NamingTests.pas (DUnitX). Do not edit by hand: edit the DUnitX
  master and run the script again. }

{ Tests for the naming options and the strict mode: JsonSnakeCase's rule
  (acronyms, digits, existing underscores), jnSnakeCase both ways and what
  else still matches when reading, RenameMember (keyword members, only the
  new name matches, inherited by descendants, a descendant renaming again,
  bad arguments), two properties sharing a JSON name, and UnknownMembers :=
  umError (paths in nested objects and arrays, nothing assigned when a body
  is rejected), and Members (what documentation tools read). The defaults
  stay camelCase and umIgnore.

  DUnitX master, written in FPCUnit's assertion dialect (TAssert.*, through
  PascalJsonMapper.DUnitXCompat). The mirror in tests/Unit/fpc is generated
  from the master by tools/gen_fpc_mirror.py — edit only the master. }

interface

uses
  fpcunit, testregistry,
  SysUtils,
  PascalJsonMapper.Json,
  PascalJsonMapper.Mapper,
  PascalJsonMapper.TestTypes;

type
  TNamingTests = class(TTestCase)
  private
    FMapper: TJsonMapper;
    function NewNaming: TNamingDto;
    procedure AssertRaises(const AJson, AExpectedStart: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure Defaults_AreUnchanged;
    procedure SnakeCase_Rule;
    procedure SnakeCase_Write;
    procedure SnakeCase_Read_AlsoMatchesCaseAndDeclaredName;
    procedure Rename_KeywordMember_BothWays;
    procedure Rename_OnlyTheNewNameMatches;
    procedure Rename_InheritedAndOverridden;
    procedure Rename_BadArguments_Raise;
    procedure Collision_Raises;
    procedure Strict_UnknownMember_RaisesWithPath;
    procedure Strict_NestedAndArrayPaths;
    procedure Strict_KnownVariants_Pass;
    procedure Strict_RejectedBody_ChangesNothing;
    procedure Members_NamesTypesAndOrder;
    procedure Members_FollowNamingAndRenames;
    procedure Members_Collision_Raises;
  end;

implementation

{ TNamingTests }

procedure TNamingTests.SetUp;
begin
  FMapper := NewTestMapper;
end;

procedure TNamingTests.TearDown;
begin
  FreeAndNil(FMapper);
end;

function TNamingTests.NewNaming: TNamingDto;
begin
  Result := TNamingDto.Create;
  Result.UserID := 7;
  Result.HTTPStatus := 404;
  Result.CreatedAt := 'today';
  Result.Kind := 'admin';
end;

procedure TNamingTests.AssertRaises(const AJson, AExpectedStart: string);
var
  Dto: INamingDto;
begin
  try
    Dto := FMapper.FromJson<INamingDto>(AJson);
    TAssert.Fail('Must raise: ' + AJson);
  except
    on E: EJsonMapperError do
      TAssert.AssertTrue('"' + E.Message + '" must start with "' + AExpectedStart + '"',
        Pos(AExpectedStart, E.Message) = 1);
  end;
end;

procedure TNamingTests.Defaults_AreUnchanged;
var
  M: TJsonMapper;
begin
  M := TJsonMapper.Create;
  try
    TAssert.AssertTrue(M.Naming = jnCamelCase);
    TAssert.AssertTrue(M.UnknownMembers = umIgnore);
    TAssert.AssertEquals(0, M.Indent);
  finally
    M.Free;
  end;
end;

procedure TNamingTests.SnakeCase_Rule;
begin
  TAssert.AssertEquals('created_at', JsonSnakeCase('CreatedAt'));
  TAssert.AssertEquals('user_id', JsonSnakeCase('UserID'));
  TAssert.AssertEquals('http_status', JsonSnakeCase('HTTPStatus'));
  TAssert.AssertEquals('io_stream', JsonSnakeCase('IOStream'));
  TAssert.AssertEquals('id', JsonSnakeCase('Id'));
  TAssert.AssertEquals('id', JsonSnakeCase('ID'));
  TAssert.AssertEquals('x', JsonSnakeCase('X'));
  TAssert.AssertEquals('address2', JsonSnakeCase('Address2'));
  TAssert.AssertEquals('line2_text', JsonSnakeCase('Line2Text'));
  TAssert.AssertEquals('already_snake', JsonSnakeCase('Already_Snake'));
  TAssert.AssertEquals('name_', JsonSnakeCase('Name_'));
  TAssert.AssertEquals('lower', JsonSnakeCase('lower'));
  TAssert.AssertEquals('', JsonSnakeCase(''));
end;

procedure TNamingTests.SnakeCase_Write;
var
  Dto: INamingDto;
begin
  FMapper.Naming := jnSnakeCase;
  Dto := NewNaming;
  TAssert.AssertEquals('{"user_id":7,"http_status":404,"created_at":"today","kind":"admin"}',
    FMapper.ToJson<INamingDto>(Dto));
end;

procedure TNamingTests.SnakeCase_Read_AlsoMatchesCaseAndDeclaredName;
var
  Dto: INamingDto;
  D: TNamingDto;
begin
  FMapper.Naming := jnSnakeCase;
  Dto := FMapper.FromJson<INamingDto>('{"user_id":1,"HTTP_STATUS":2,"CreatedAt":"c"}');
  D := Dto as TNamingDto;
  TAssert.AssertEquals(1, D.UserID);
  TAssert.AssertEquals(2, D.HTTPStatus);
  TAssert.AssertEquals('c', D.CreatedAt);
end;

procedure TNamingTests.Rename_KeywordMember_BothWays;
var
  Dto: INamingDto;
begin
  FMapper.RenameMember(TNamingDto, 'Kind', 'type');
  Dto := NewNaming;
  TAssert.AssertEquals('{"userID":7,"hTTPStatus":404,"createdAt":"today","type":"admin"}',
    FMapper.ToJson<INamingDto>(Dto));
  Dto := FMapper.FromJson<INamingDto>('{"type":"guest"}');
  TAssert.AssertEquals('guest', (Dto as TNamingDto).Kind);
  // A rename beats Naming.
  FMapper.Naming := jnSnakeCase;
  TAssert.AssertEquals('{"user_id":7,"http_status":404,"created_at":"today","type":"admin"}',
    FMapper.ToJson<INamingDto>(NewNaming));
end;

procedure TNamingTests.Rename_OnlyTheNewNameMatches;
var
  Dto: INamingDto;
begin
  FMapper.RenameMember(TNamingDto, 'kind', 'type');
  Dto := FMapper.FromJson<INamingDto>('{"kind":"ignored","TYPE":"kept"}');
  TAssert.AssertEquals('kept', (Dto as TNamingDto).Kind);
  Dto := FMapper.FromJson<INamingDto>('{"kind":"ignored"}');
  TAssert.AssertEquals('', (Dto as TNamingDto).Kind);
  FMapper.UnknownMembers := umError;
  AssertRaises('{"kind":"x"}', '$.kind: unknown member');
end;

procedure TNamingTests.Rename_InheritedAndOverridden;
var
  Child: TNamingChildDto;
  Base: TNamingDto;
begin
  FMapper.RenameMember(TNamingDto, 'Kind', 'type');
  Child := TNamingChildDto.Create;
  Base := TNamingDto.Create;
  try
    Child.Kind := 'k';
    Base.Kind := 'k';
    TAssert.AssertTrue(Pos('"type":"k"', FMapper.ObjectToJson(Child)) > 0);
    FMapper.RenameMember(TNamingChildDto, 'Kind', 'category');
    TAssert.AssertTrue(Pos('"category":"k"', FMapper.ObjectToJson(Child)) > 0);
    TAssert.AssertTrue(Pos('"type":"k"', FMapper.ObjectToJson(Base)) > 0);
  finally
    Child.Free;
    Base.Free;
  end;
end;

procedure TNamingTests.Rename_BadArguments_Raise;
begin
  try
    FMapper.RenameMember(TNamingDto, 'Missing', 'x');
    TAssert.Fail('An unknown property must raise');
  except
    on E: EJsonMapperError do
      TAssert.AssertTrue(E.Message, Pos('"Missing"', E.Message) > 0);
  end;
  try
    FMapper.RenameMember(TNamingDto, 'Kind', '');
    TAssert.Fail('An empty name must raise');
  except
    on E: EJsonMapperError do
      ;
  end;
end;

procedure TNamingTests.Collision_Raises;
var
  Dto: ICollisionDto;
  Json: string;
begin
  // camelCase keeps them apart ("userId" / "user_Id")...
  Dto := TCollisionDto.Create;
  Json := FMapper.ToJson<ICollisionDto>(Dto);
  TAssert.AssertEquals('{"userId":0,"user_Id":0}', Json);
  // ...snake_case doesn't: both are user_id.
  FMapper.Naming := jnSnakeCase;
  try
    FMapper.ToJson<ICollisionDto>(Dto);
    TAssert.Fail('A shared JSON name must raise');
  except
    on E: EJsonMapperError do
      TAssert.AssertTrue(E.Message, (Pos('UserId', E.Message) > 0) and
        (Pos('User_Id', E.Message) > 0) and (Pos('"user_id"', E.Message) > 0));
  end;
  // A rename that lands on another property's name collides as well.
  FMapper.Naming := jnCamelCase;
  FMapper.RenameMember(TNamingDto, 'Kind', 'UserID');
  try
    FMapper.ToJson<INamingDto>(NewNaming);
    TAssert.Fail('A rename onto another member must raise');
  except
    on E: EJsonMapperError do
      TAssert.AssertTrue(E.Message, Pos('both map', E.Message) > 0);
  end;
end;

procedure TNamingTests.Strict_UnknownMember_RaisesWithPath;
begin
  FMapper.UnknownMembers := umError;
  AssertRaises('{"userID":1,"nmae":"x"}', '$.nmae: unknown member');
end;

procedure TNamingTests.Strict_NestedAndArrayPaths;
var
  Dto: IOrderDto;
begin
  FMapper.UnknownMembers := umError;
  try
    Dto := FMapper.FromJson<IOrderDto>('{"item":{"code":1,"cod":2}}');
    TAssert.Fail('Must raise');
  except
    on E: EJsonMapperError do
      TAssert.AssertTrue(E.Message, Pos('$.item.cod: unknown member', E.Message) = 1);
  end;
  try
    Dto := FMapper.FromJson<IOrderDto>('{"itens":[{"code":1},{"code":2,"x":0}]}');
    TAssert.Fail('Must raise');
  except
    on E: EJsonMapperError do
      TAssert.AssertTrue(E.Message, Pos('$.itens[1].x: unknown member', E.Message) = 1);
  end;
end;

procedure TNamingTests.Strict_KnownVariants_Pass;
var
  Dto: IScalarDto;
begin
  FMapper.UnknownMembers := umError;
  // Case variants, the declared name, a read-only and an inherited property.
  Dto := FMapper.FromJson<IScalarDto>(
    '{"NOME":"a","Idade":1,"somenteLeitura":"ignored","id":5}');
  TAssert.AssertEquals('a', (Dto as TScalarDto).Nome);
  TAssert.AssertEquals(Int64(5), (Dto as TScalarDto).Id);
end;

procedure TNamingTests.Strict_RejectedBody_ChangesNothing;
var
  P: TPerson;
begin
  FMapper.UnknownMembers := umError;
  P := TPerson.Create;
  try
    P.Name := 'before';
    try
      FMapper.PopulateObject(P, '{"name":"after","nickname":"x"}');
      TAssert.Fail('Must raise');
    except
      on E: EJsonMapperError do
        TAssert.AssertTrue(E.Message, Pos('$.nickname: unknown member', E.Message) = 1);
    end;
    TAssert.AssertEquals('before', P.Name);
  finally
    P.Free;
  end;
end;

procedure TNamingTests.Members_NamesTypesAndOrder;
var
  M: TJsonMemberArray;
begin
  // Ancestors first, then declaration order: what ToJson writes.
  M := FMapper.Members(TNamingChildDto);
  TAssert.AssertEquals(5, Length(M));
  TAssert.AssertEquals('UserID', M[0].PropertyName);
  TAssert.AssertEquals('userID', M[0].JsonName);
  TAssert.AssertTrue('UserID is an Integer', M[0].TypeInfo = TypeInfo(Integer));
  TAssert.AssertEquals('CreatedAt', M[2].PropertyName);
  TAssert.AssertTrue('CreatedAt is a string', M[2].TypeInfo = TypeInfo(string));
  TAssert.AssertEquals('Extra', M[4].PropertyName);
  TAssert.AssertTrue(M[4].Readable and M[4].Writable);
end;

procedure TNamingTests.Members_FollowNamingAndRenames;
var
  M: TJsonMemberArray;
begin
  FMapper.Naming := jnSnakeCase;
  FMapper.RenameMember(TNamingDto, 'Kind', 'type');
  M := FMapper.Members(TNamingDto);
  TAssert.AssertEquals('user_id', M[0].JsonName);
  TAssert.AssertEquals('http_status', M[1].JsonName);
  TAssert.AssertEquals('type', M[3].JsonName);
  // The same names ToJson uses.
  TAssert.AssertEquals('{"user_id":7,"http_status":404,"created_at":"today","type":"admin"}',
    FMapper.ToJson<INamingDto>(NewNaming));
end;

procedure TNamingTests.Members_Collision_Raises;
begin
  FMapper.Naming := jnSnakeCase;
  try
    FMapper.Members(TCollisionDto);
    TAssert.Fail('A collision must raise');
  except
    on E: EJsonMapperError do
      TAssert.AssertTrue(E.Message, Pos('"user_id"', E.Message) > 0);
  end;
end;

initialization
  RegisterTest(TNamingTests);

end.
