port module Main exposing (Model, init, main)

import Bootstrap.Alert as Alert
import Bootstrap.Button as Button
import Bootstrap.Card as Card
import Bootstrap.Card.Block as Block
import Bootstrap.Form as Form
import Bootstrap.Form.Fieldset as Fieldset
import Bootstrap.Form.Input as Input
import Bootstrap.Form.InputGroup as InputGroup
import Bootstrap.Form.Textarea as Textarea
import Bootstrap.Grid as Grid
import Bootstrap.Grid.Col as Col
import Bootstrap.Grid.Row as Row
import Bootstrap.ListGroup as ListGroup
import Bootstrap.Modal as Modal
import Bootstrap.Navbar as Navbar
import Bootstrap.Spinner as Spinner
import Bootstrap.Text as Text
import Bootstrap.Utilities.Spacing as Spacing
import Browser
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Http
import Json.Decode as D
import Json.Encode as E
import Loading exposing (LoaderType(..), defaultConfig, render)


main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }



-- PORT


port saveAuth : E.Value -> Cmd msg


port loadAuth : (E.Value -> msg) -> Sub msg


port requestNews : E.Value -> Cmd msg


port newsResponse : (E.Value -> msg) -> Sub msg


port filmRequest : E.Value -> Cmd msg


port filmResponse : (E.Value -> msg) -> Sub msg


port videoSourceRequest : E.Value -> Cmd msg


port videoSourceResponse : (E.Value -> msg) -> Sub msg


port createNewsRequest : E.Value -> Cmd msg


port createNewsResponse : (E.Value -> msg) -> Sub msg


port acceptNewsRequest : E.Value -> Cmd msg


port acceptNewsResponse : (E.Value -> msg) -> Sub msg


port rejectNewsRequest : E.Value -> Cmd msg


port rejectNewsResponse : (E.Value -> msg) -> Sub msg


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ loadAuth LoadAuth
        , newsResponse GotNews
        , filmResponse GotFilm
        , videoSourceResponse PlayVideo
        , createNewsResponse NewsCreationResponse
        , acceptNewsResponse GotAcceptedNews
        , rejectNewsResponse GotRejectedNews
        ]



-- MODEL


type alias AuthResult =
    { authToken : String
    , expires : String
    , isFirstLogin : Bool
    }


type alias Credentials =
    { email : String
    , password : String
    , token : Maybe String
    }


type alias Model =
    { credentials : Credentials
    , request : Request
    , alertVisibility : Alert.Visibility
    , news : List News
    , editor : Editor
    , navbarState : Navbar.State
    , newsTemplate : CreateNewsTemplate
    , createNewsStatus : CreateNews
    , selectedNews : Maybe News
    }


type CreateNews
    = Ready
    | Busy


type alias CreateNewsTemplate =
    { title : String
    , description : String
    , url : String
    }


type Editor
    = Initial
    | LoadingVideo
    | PlayingVideo String
    | Error String
    | Message String
    | AddNews


type Request
    = NotSentYet
    | Failure Reason
    | Loading
    | Success


type alias News =
    { id : Int
    , title : String
    , fileId : Int
    }


type Reason
    = Unauthorized
    | Other String



-- INIT


init : () -> ( Model, Cmd Msg )
init _ =
    let
        ( navbarState, navbarCmd ) =
            Navbar.initialState NavbarMsg
    in
    ( Model
        { email = ""
        , password = ""
        , token = Nothing
        }
        NotSentYet
        Alert.closed
        []
        Initial
        navbarState
        clearNewsFormData
        Ready
        Nothing
    , navbarCmd
    )



-- HTTP


obtainToken : String -> String -> Cmd Msg
obtainToken email password =
    Http.post
        { url = "http://3.120.74.192:9090/rest/authentication"
        , body = Http.jsonBody (encodeRequestBody email password)
        , expect = Http.expectJson GotToken decodeAuthResult
        }


handleAuthResponse : Result Http.Error AuthResult -> Model -> ( Model, Cmd Msg )
handleAuthResponse response model =
    case response of
        Ok authResult ->
            let
                token =
                    authResult.authToken

                credentials =
                    model.credentials
            in
            ( { model
                | request = Success
                , credentials = { credentials | token = Just token }
                , alertVisibility = Alert.closed
              }
            , Cmd.batch
                [ saveAuth <| encodeAuthResult authResult
                , requestNews <| E.string token
                ]
            )

        Err error ->
            case error of
                Http.BadUrl url ->
                    ( { model
                        | request = Failure <| Other <| "Bad url: " ++ url
                        , alertVisibility = Alert.shown
                      }
                    , Cmd.none
                    )

                Http.Timeout ->
                    ( { model
                        | request = Failure <| Other "Request timeout"
                        , alertVisibility = Alert.shown
                      }
                    , Cmd.none
                    )

                Http.NetworkError ->
                    ( { model
                        | request = Failure <| Other "Network error"
                        , alertVisibility = Alert.shown
                      }
                    , Cmd.none
                    )

                Http.BadStatus code ->
                    handleStatusCode code model

                Http.BadBody _ ->
                    ( { model
                        | request = Failure <| Other "Unexpected content received"
                        , alertVisibility = Alert.shown
                      }
                    , Cmd.none
                    )


handleStatusCode : Int -> Model -> ( Model, Cmd Msg )
handleStatusCode code model =
    case code of
        401 ->
            ( { model
                | request = Failure Unauthorized
                , alertVisibility = Alert.shown
              }
            , Cmd.none
            )

        _ ->
            ( model, Cmd.none )



-- ENCODE DECODE


decodeAddNewsResponse : D.Decoder String
decodeAddNewsResponse =
    D.field "statusCode" D.string


encodeNewsTemplate : CreateNewsTemplate -> E.Value
encodeNewsTemplate template =
    E.object
        [ ( "title", E.string template.title )
        , ( "description", E.string template.description )
        , ( "url", E.string template.url )
        ]


decodeFilm : D.Decoder (Maybe Int)
decodeFilm =
    D.map List.head
        (D.list (D.field "id" D.int))


decodeNewsList : D.Decoder (List News)
decodeNewsList =
    D.list decodeNews


decodeNews : D.Decoder News
decodeNews =
    D.map3 News
        (D.field "id" D.int)
        (D.field "title" D.string)
        (D.field "fileId" D.int)


encodeNewsList : List News -> E.Value
encodeNewsList news =
    E.list encodeNews news


encodeNews : News -> E.Value
encodeNews news =
    E.object
        [ ( "id", E.int news.id )
        , ( "title", E.string news.title )
        , ( "fileId", E.int news.fileId )
        ]


decodeAuthResult : D.Decoder AuthResult
decodeAuthResult =
    D.map3 AuthResult
        (D.field "authToken" D.string)
        (D.field "expires" D.string)
        (D.field "isFirstLogin" D.bool)


encodeAuthResult : AuthResult -> E.Value
encodeAuthResult authResult =
    E.object
        [ ( "authToken", E.string authResult.authToken )
        , ( "expires", E.string authResult.expires )
        , ( "isFirstLogin", E.bool authResult.isFirstLogin )
        ]


encodeRequestBody : String -> String -> E.Value
encodeRequestBody email password =
    E.object
        [ ( "email", E.string email )
        , ( "password", E.string password )
        ]



-- UPDATE


type Msg
    = InputEmail String
    | InputPassword String
    | SignIn
    | SignOut
    | GotToken (Result Http.Error AuthResult)
      -- | GotNews (Result Http.Error (List News))
    | AlertMsg Alert.Visibility
    | LoadAuth E.Value
    | PlayVideo E.Value
    | Play News
    | GotNews E.Value
    | GotFilm E.Value
    | RefreshPlaylist
    | NavbarMsg Navbar.State
    | CloseNewsCreator
    | ClearNewsFormData
    | OpenNewsCreator
    | InputNewsTitle String
    | InputNewsDescription String
    | InputNewsUrl String
    | CreateNews
    | NewsCreationResponse E.Value
    | AcceptNews
    | RejectNews
    | GotAcceptedNews E.Value
    | GotRejectedNews E.Value


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        InputEmail email ->
            let
                credentials =
                    model.credentials
            in
            ( { model | credentials = { credentials | email = email } }, Cmd.none )

        InputPassword password ->
            let
                credentials =
                    model.credentials
            in
            ( { model | credentials = { credentials | password = password } }, Cmd.none )

        SignIn ->
            ( { model | alertVisibility = Alert.closed }
            , obtainToken model.credentials.email model.credentials.password
            )

        SignOut ->
            let
                credentials =
                    model.credentials

                emptyAuth =
                    E.object [ ( "status", E.string "Unauthorized" ) ]
            in
            ( { model
                | credentials =
                    { credentials
                        | token = Nothing
                    }
              }
            , saveAuth emptyAuth
            )

        AlertMsg visibility ->
            ( { model | alertVisibility = visibility }, Cmd.none )

        GotToken response ->
            handleAuthResponse response model

        LoadAuth encoded ->
            let
                authResult =
                    D.decodeValue
                        decodeAuthResult
                        encoded

                token =
                    case authResult of
                        Ok result ->
                            Just result.authToken

                        Err _ ->
                            Nothing

                credentials =
                    model.credentials
            in
            ( { model
                | credentials =
                    { credentials | token = token }
              }
            , case token of
                Just value ->
                    requestNews <| E.string value

                Nothing ->
                    Cmd.none
            )

        PlayVideo encoded ->
            let
                editor =
                    case
                        D.decodeValue
                            (D.field "url" D.string)
                            encoded
                    of
                        Ok url ->
                            PlayingVideo url

                        Err error ->
                            Error <| D.errorToString error
            in
            ( { model
                | editor =
                    editor
              }
            , Cmd.none
            )

        Play news ->
            ( { model
                | selectedNews = Just news
                , editor = LoadingVideo
              }
            , filmRequest <|
                E.string <|
                    String.fromInt
                        news.fileId
            )

        GotNews encoded ->
            let
                news =
                    case D.decodeValue decodeNewsList encoded of
                        Ok value ->
                            value

                        Err _ ->
                            []
            in
            ( { model | news = news }
            , Cmd.none
            )

        GotFilm encoded ->
            ( model
            , case D.decodeValue decodeFilm encoded of
                Ok value ->
                    case value of
                        Just filmId ->
                            videoSourceRequest <|
                                E.string <|
                                    String.fromInt
                                        filmId

                        Nothing ->
                            -- let
                            --     log =
                            --         Debug.log "No Films found" ""
                            -- in
                            -- -- TODO Alert about empty data
                            Cmd.none

                Err message ->
                    -- let
                    --     log =
                    --         Debug.log "Film decode error" message
                    -- in
                    -- TODO Alert about decoder failure
                    Cmd.none
            )

        RefreshPlaylist ->
            ( model
            , Cmd.batch
                [ case model.credentials.token of
                    Just token ->
                        requestNews <| E.string token

                    Nothing ->
                        Cmd.none

                -- , filmRequest <|
                --     E.string <|
                --         String.fromInt
                --             90
                ]
            )

        NavbarMsg state ->
            ( { model | navbarState = state }, Cmd.none )

        CloseNewsCreator ->
            ( { model | editor = Initial }, Cmd.none )

        ClearNewsFormData ->
            ( { model
                | editor = AddNews
                , newsTemplate = clearNewsFormData
              }
            , Cmd.none
            )

        OpenNewsCreator ->
            ( { model | editor = AddNews }, Cmd.none )

        InputNewsTitle title ->
            let
                origTemplate =
                    model.newsTemplate
            in
            ( { model
                | newsTemplate =
                    { origTemplate | title = title }
              }
            , Cmd.none
            )

        InputNewsDescription description ->
            let
                origTemplate =
                    model.newsTemplate
            in
            ( { model
                | newsTemplate =
                    { origTemplate | description = description }
              }
            , Cmd.none
            )

        InputNewsUrl url ->
            let
                origTemplate =
                    model.newsTemplate
            in
            ( { model
                | newsTemplate =
                    { origTemplate | url = url }
              }
            , Cmd.none
            )

        CreateNews ->
            ( { model | createNewsStatus = Busy }
            , createNewsRequest <|
                encodeNewsTemplate model.newsTemplate
            )

        NewsCreationResponse encoded ->
            let
                responseStatus =
                    case D.decodeValue decodeAddNewsResponse encoded of
                        Ok status ->
                            if status == "OK" then
                                Error "News successfuly added"

                            else
                                Error "Could not add news"

                        Err _ ->
                            Error "Could not add news"
            in
            ( { model
                | editor = responseStatus
                , createNewsStatus = Ready
                , newsTemplate = clearNewsFormData
              }
            , Cmd.none
            )

        AcceptNews ->
            ( model
            , case model.selectedNews of
                Just news ->
                    acceptNewsRequest <|
                        E.string <|
                            String.fromInt news.id

                Nothing ->
                    -- TODO Tell user about this case
                    Cmd.none
            )

        RejectNews ->
            ( model
            , case model.selectedNews of
                Just news ->
                    rejectNewsRequest <|
                        E.string <|
                            String.fromInt news.id

                Nothing ->
                    -- TODO tell user about this case
                    Cmd.none
            )

        GotAcceptedNews encoded ->
            let
                editor =
                    case
                        D.decodeValue
                            (D.field "statusCode" D.string)
                            encoded
                    of
                        Ok message ->
                            if message == "NO_CONTENT" then
                                Message "Accepted"

                            else
                                Error "Failed to accept"

                        Err message ->
                            Error <| D.errorToString message
            in
            ( { model | editor = editor }, Cmd.none )

        GotRejectedNews encoded ->
            let
                editor =
                    case
                        D.decodeValue
                            (D.field "statusCode" D.string)
                            encoded
                    of
                        Ok message ->
                            if message == "NO_CONTENT" then
                                Message "Rejected"

                            else
                                Error "Failed to reject"

                        Err err ->
                            Error <| D.errorToString err
            in
            ( { model | editor = editor }, Cmd.none )



-- HELPER


clearNewsFormData : CreateNewsTemplate
clearNewsFormData =
    { title = ""
    , description = ""
    , url = ""
    }



-- VIEW


view : Model -> Html Msg
view model =
    case model.credentials.token of
        Just token ->
            div []
                [ viewNavbar model
                , viewAdmin model
                ]

        Nothing ->
            viewSignIn model


viewNavbar : Model -> Html Msg
viewNavbar model =
    Grid.container []
        -- Wrap in a container to center the navbar
        [ Navbar.config NavbarMsg
            |> Navbar.withAnimation
            |> Navbar.collapseMedium
            -- Collapse menu at the medium breakpoint
            |> Navbar.info
            -- Customize coloring
            -- |> Navbar.brand
            --     -- Add logo to your brand with a little styling to align nicely
            --     [ href "#" ]
            --     [ img
            --         [ src "assets/images/elm-bootstrap.svg"
            --         , class "d-inline-block align-top"
            --         , style [ ( "width", "30px" ) ]
            --         ]
            --         []
            --     , text " Elm Bootstrap"
            --     ]
            -- |> Navbar.items
            --     [ Navbar.itemLink
            --         [ href "#" ]
            --         [ text "Item 1" ]
            --     , Navbar.dropdown
            --         -- Adding dropdowns is pretty simple
            --         { id = "mydropdown"
            --         , toggle = Navbar.dropdownToggle [] [ text "My dropdown" ]
            --         , items =
            --             [ Navbar.dropdownHeader [ text "Heading" ]
            --             , Navbar.dropdownItem
            --                 [ href "#" ]
            --                 [ text "Drop item 1" ]
            --             , Navbar.dropdownItem
            --                 [ href "#" ]
            --                 [ text "Drop item 2" ]
            --             , Navbar.dropdownDivider
            --             , Navbar.dropdownItem
            --                 [ href "#" ]
            --                 [ text "Drop item 3" ]
            --             ]
            --         }
            --     ]
            |> Navbar.customItems
                [ Navbar.formItem []
                    [ Button.button
                        [ Button.warning
                        , Button.attrs [ Spacing.ml2Sm ]
                        , Button.onClick SignOut
                        ]
                        [ text "Sign out" ]
                    ]
                ]
            |> Navbar.view model.navbarState
        ]


viewAdmin : Model -> Html Msg
viewAdmin model =
    Grid.container []
        [ Grid.row []
            [ Grid.col [] [ viewDashboard model ]
            , Grid.col [] [ viewEditor model ]
            ]
        ]


viewDashboard : Model -> Html Msg
viewDashboard model =
    Card.config
        [ Card.align Text.alignXsCenter ]
        |> Card.header []
            [ div []
                [ Button.button
                    [ Button.primary
                    , Button.attrs [ Spacing.mr3 ]
                    , Button.onClick RefreshPlaylist
                    ]
                    [ text "Refresh" ]
                , Button.button
                    [ Button.primary
                    , Button.attrs [ Spacing.ml3 ]
                    , Button.onClick OpenNewsCreator
                    ]
                    [ text "Create news" ]
                ]
            ]
        |> Card.block []
            [ Block.text []
                [ ListGroup.custom <|
                    List.map viewNews model.news
                ]
            ]
        |> Card.view


viewEditor : Model -> Html Msg
viewEditor model =
    case model.editor of
        Initial ->
            Card.config [ Card.attrs [ width 20 ] ]
                |> Card.header [ class "text-center" ]
                    [ h3 [ Spacing.mt2 ]
                        [ text <|
                            "Click to one of the"
                                ++ " videos listed in the"
                                ++ " left to play it !"
                        ]
                    ]
                |> Card.view

        LoadingVideo ->
            Card.config [ Card.attrs [ width 20 ] ]
                |> Card.header [ class "text-center" ]
                    [ Loading.render
                        Loading.Spinner
                        -- LoaderType
                        { defaultConfig
                            | color = "#d3869b"
                            , size = 150
                        }
                        -- Config
                        Loading.On
                    ]
                |> Card.view

        PlayingVideo url ->
            let
                ( video, actions ) =
                    videoPlayer url model.selectedNews
            in
            Card.config
                [ Card.align Text.alignXsCenter
                , Card.attrs [ width 20 ]
                ]
                |> Card.header [ class "text-center" ]
                    [ video ]
                |> Card.footer [] [ actions ]
                |> Card.view

        Error message ->
            Card.config [ Card.attrs [ width 20 ] ]
                |> Card.header [ class "text-center" ]
                    [ h3 [ Spacing.mt2 ] [ text message ] ]
                |> Card.view

        Message message ->
            Card.config [ Card.attrs [ width 20 ] ]
                |> Card.header [ class "text-center" ]
                    [ h3 [ Spacing.mt2 ] [ text message ] ]
                |> Card.view

        AddNews ->
            Card.config [ Card.attrs [ width 20 ] ]
                |> Card.header [ class "text-center" ]
                    [ viewAddNews model ]
                |> Card.view


videoPlayer : String -> Maybe News -> ( Html Msg, Html Msg )
videoPlayer url value =
    let
        actionButton : String -> Msg -> Button.Option Msg -> Attribute Msg -> Html Msg
        actionButton name msg color attribute =
            case value of
                Just news ->
                    Button.button
                        (color
                            :: [ Button.attrs [ attribute ]
                               , Button.onClick msg
                               ]
                        )
                        [ text name ]

                Nothing ->
                    Button.button
                        (color
                            :: [ Button.disabled True
                               , Button.attrs [ attribute ]
                               , Button.onClick msg
                               ]
                        )
                        [ text name ]
    in
    ( div []
        [ video
            [ width 320
            , height 240
            , autoplay True
            , src url
            ]
            []
        ]
    , div []
        [ actionButton "Accept" AcceptNews Button.success Spacing.mr3
        , actionButton "Reject" RejectNews Button.danger Spacing.ml3
        ]
    )


viewNews : News -> ListGroup.CustomItem Msg
viewNews news =
    ListGroup.button
        [ ListGroup.primary
        , ListGroup.attrs [ onClick (Play news) ]
        ]
        [ text news.title ]


viewSignIn : Model -> Html Msg
viewSignIn model =
    div []
        [ Alert.config
            |> Alert.warning
            |> Alert.dismissable AlertMsg
            |> Alert.children
                [ Alert.h6 [] [ text (getErrorMessage model.request) ] ]
            |> Alert.view model.alertVisibility
        , Grid.container []
            [ Grid.row [ Row.centerMd, Row.middleXs ]
                [ Grid.col
                    [ Col.sm4 ]
                    [ h3
                        []
                        [ text "Newsable admin" ]
                    , Form.form []
                        [ Form.group []
                            [ InputGroup.config
                                (InputGroup.email <|
                                    viewInput model.request
                                        "email"
                                        model.credentials.email
                                        InputEmail
                                )
                                |> InputGroup.predecessors
                                    [ InputGroup.span [] [ text "@" ] ]
                                |> InputGroup.view
                            ]
                        , Form.group []
                            [ InputGroup.config
                                (InputGroup.password <|
                                    viewInput model.request
                                        "password"
                                        model.credentials.password
                                        InputPassword
                                )
                                |> InputGroup.predecessors
                                    [ InputGroup.span [] [ text "*" ] ]
                                |> InputGroup.view
                            , Form.help [] [ text "Minimum 6 characters" ]
                            ]
                        , Grid.row
                            [ Row.betweenXs ]
                            [ Grid.col []
                                [ Button.button
                                    [ Button.primary
                                    , Button.onClick SignIn
                                    ]
                                    [ text "Sign In" ]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]


getErrorMessage : Request -> String
getErrorMessage request =
    case request of
        Failure type_ ->
            case type_ of
                Other message ->
                    message

                Unauthorized ->
                    "Invalid EMAIL or PASSWORD"

        _ ->
            ""


viewInput : Request -> String -> String -> (String -> Msg) -> List (Input.Option Msg)
viewInput request placeholder value command =
    let
        regularInput =
            [ Input.placeholder placeholder
            , Input.value value
            , Input.onInput command
            ]
    in
    case request of
        Failure type_ ->
            case type_ of
                Unauthorized ->
                    Input.danger :: regularInput

                _ ->
                    regularInput

        _ ->
            regularInput


viewAddNews : Model -> Html Msg
viewAddNews model =
    Form.form []
        [ Form.group []
            [ Form.label [ for "title" ] [ text "Title" ]
            , Input.text
                [ Input.id "title"
                , Input.onInput InputNewsTitle
                , Input.value model.newsTemplate.title
                ]
            ]
        , Form.group []
            [ label [ for "description" ] [ text "Description" ]
            , Textarea.textarea
                [ Textarea.id "description"
                , Textarea.rows 3
                , Textarea.onInput InputNewsDescription
                , Textarea.value model.newsTemplate.description
                ]
            ]
        , Form.group []
            [ Form.label [ for "url" ] [ text "Url" ]
            , Input.text
                [ Input.id "url"
                , Input.onInput InputNewsUrl
                , Input.value model.newsTemplate.url
                ]
            ]
        , viewSaveButton model
        , Button.button
            [ Button.warning
            , Button.attrs [ Spacing.ml1 ]
            , Button.onClick ClearNewsFormData
            ]
            [ text "Clear form" ]
        , Button.button
            [ Button.warning
            , Button.attrs [ Spacing.ml1 ]
            , Button.onClick CloseNewsCreator
            ]
            [ text "Close" ]
        ]


viewSaveButton : Model -> Html Msg
viewSaveButton model =
    case model.createNewsStatus of
        Ready ->
            viewAddNewsButton model.newsTemplate

        Busy ->
            viewBusyButton


viewAddNewsButton : CreateNewsTemplate -> Html Msg
viewAddNewsButton template =
    if
        template.title
            == ""
            || template.description
            == ""
            || template.url
            == ""
    then
        Button.button
            [ Button.primary
            , Button.disabled True
            , Button.attrs [ Spacing.ml1 ]
            ]
            [ text "Add news" ]

    else
        Button.button
            [ Button.primary
            , Button.attrs [ Spacing.ml1 ]
            , Button.onClick CreateNews
            ]
            [ text "Add news" ]


viewBusyButton : Html Msg
viewBusyButton =
    Button.button
        [ Button.primary
        , Button.disabled True
        , Button.attrs [ Spacing.mr1 ]
        ]
        [ Loading.render
            Loading.BouncingBalls
            -- LoaderType
            { defaultConfig
                | color = "#fabd2f"
                , size = 23
            }
            -- Config
            Loading.On

        -- LoadingState
        ]
