--[-------------------------------------------------------]
--[ Includes                                              ]
--[-------------------------------------------------------]
require("Data/Scripts/Lua/GUI")			-- GUI script component class
require("Data/Scripts/Lua/PLGui")		-- PLGui script helper class
require("Data/Scripts/Lua/MakingOf")	-- Making of script component class


--[-------------------------------------------------------]
--[ Classes                                               ]
--[-------------------------------------------------------]
--@brief
--  Interaction script component class
Interaction = {


	--[-------------------------------------------------------]
	--[ Public definitions                                    ]
	--[-------------------------------------------------------]
	--@brief
	--   Interaction mode
	Mode = {
		WALK     = 0,	-- Walk mode
		FREE     = 1,	-- Free mode
		GHOST    = 2,	-- Ghost mode
		MOVIE    = 3,	-- Movie mode
		MAKINGOF = 4,	-- Making of mode
		UNKNOWN  = 5,	-- Unknown mode
	},


	--@brief
	--  The default constructor - In Lua a static method
	--
	--@param[in] cppApplication
	--  C++ RTTI application class instance
	--@param[in] luaApplication
	--  Lua script application class instance
	new = function(cppApplication, luaApplication)


		--[-------------------------------------------------------]
		--[ Private class attributes                              ]
		--[-------------------------------------------------------]
		local this						= {}						-- A private class attribute -> Emulates the C++ "this"-pointer by using a Lua table
		local _gui						= GUI.new(cppApplication)	-- An instance of the GUI script component class
		local _oldFilmPostProcess 		= 0							-- Old film post process effect factor (0 = not visible, 1 = fully visible)
		local _mode						= Interaction.Mode.UNKNOWN	-- The current interaction mode
		local _modeBackup				= Interaction.Mode.UNKNOWN	-- A mode backup, used for camcorder recording
		local _walkCameraSceneNode		= nil						-- Walk camera scene node
		local _freeCameraSceneNode		= nil						-- Free camera scene node
		local _ghostCameraSceneNode		= nil						-- Ghost camera scene node
		local _makingOfCameraSceneNode	= nil						-- Making of camera scene node
		local _leftMouseButtonDown		= false						-- Is the left mouse button currently down?

		-- An instance of the making of script component class, given slot function is called by Lua when the making of playback has been finished
		local _makingOf = MakingOf.new(cppApplication, luaApplication,
			function()
				-- Change into the free mode or start the movie again
				if cppApplication:IsRepeatMode() then
					this.OnSetMode(Interaction.Mode.MOVIE)
				else
					this.OnSetMode(Interaction.Mode.FREE)
				end
			end
		)


		--[-------------------------------------------------------]
		--[ Private class methods                                 ]
		--[-------------------------------------------------------]
		--@brief
		--  Updates the old film post process effect
		local function UpdateOldFilm()
			-- Get the currently set camera scene node
			local cameraSceneNode = cppApplication:GetCamera()
			if cameraSceneNode ~= nil and cameraSceneNode:GetContainer() ~= nil then
				-- Get the current time difference
				local timeDiff = PL.Timing.GetTimeDifference()/4

				-- Update the the old film post process effect factor
				local containerName = cameraSceneNode:GetContainer().Name
				if containerName == "kanal2" or containerName == "kanal4" then
					_oldFilmPostProcess = _oldFilmPostProcess + timeDiff
					if _oldFilmPostProcess > 1 then
						_oldFilmPostProcess = 1
					end
				else
					_oldFilmPostProcess = _oldFilmPostProcess - timeDiff
					if _oldFilmPostProcess < 0 then
						_oldFilmPostProcess = 0
					end
				end

				-- Is there currently a old film post process effect?
				if _oldFilmPostProcess > 0 then
					-- Update "PLPostProcessEffects::SNMPostProcessOldFilm" modifier
					local sceneNodeModifier = cameraSceneNode:GetModifier("PLPostProcessEffects::SNMPostProcessOldFilm")
					if sceneNodeModifier == nil then
						sceneNodeModifier = cameraSceneNode:AddModifier("PLPostProcessEffects::SNMPostProcessOldFilm")
					end
					if sceneNodeModifier ~= nil then
						sceneNodeModifier.EffectWeight = _oldFilmPostProcess
					end
				else
					-- Remove "PLPostProcessEffects::SNMPostProcessOldFilm" modifier
					cameraSceneNode:RemoveModifier("PLPostProcessEffects::SNMPostProcessOldFilm")
				end
			end
		end

		--@brief
		--  Set mouse cursor visibility
		--
		--@param[in] visible
		--  Shall the mouse cursor be visible?
		local function SetMouseVisible(visible)
			-- Do not hide the mouse cursor if the GUI is currently visible!
			if cppApplication:GetIngameGui():IsGuiShown() then
				visible = true
			end

			-- Get the main window of the application
			local widget = cppApplication:GetMainWindow()
			if widget ~= nil then
				-- Set mouse cursor visibility
				widget:GetGui():SetMouseVisible(visible)

				-- Trap mouse inside the content widget when the mouse cursor is invisible
				widget:GetContentWidget():SetTrapMouse(not visible)
			end
		end


		--[-------------------------------------------------------]
		--[ Public class methods                                  ]
		--[-------------------------------------------------------]
		--@brief
		--  Updates the interaction script component
		function this.Update()
			-- Update the old film post process effect
			UpdateOldFilm()

			-- Update the instance of the GUI script component class
			_gui.Update()

			-- Update the instance of the making of script component class
			_makingOf.Update()
		end

		--@brief
		--  Slot function is called by C++ when a new interaction mode has been chosen
		--
		--@param[in] newMode
		--  The new mode
		--@param[in] showText
		--  Show mode changed text?
		function this.OnSetMode(newMode, showText)
			-- Mode change?
			if _mode ~= newMode then
				-- Get the camcorder component
				local camcorder = cppApplication:GetCamcorder()

				-- Stop the camcorder playback
				camcorder:StopPlayback()

				-- Stop the making of playback
				_makingOf.StopPlayback()

				-- Set the new mode
				_mode = newMode

				-- Get new camera scene node and a short text
				local modeChangedText
				local newCameraSceneNode
				-- Lua does not support switch/case statements, so we just use a Lua table (using if/else in here would be somewhat extreme)
				local action = {
					-- Walk mode
					[Interaction.Mode.WALK] = function()
						modeChangedText 	= "Walk mode"
						newCameraSceneNode	= _walkCameraSceneNode
					end,

					-- Free mode
					[Interaction.Mode.FREE] = function()
						modeChangedText		= "Free mode"
						newCameraSceneNode	= _freeCameraSceneNode
					end,

					-- Ghost mode
					[Interaction.Mode.GHOST] = function()
						modeChangedText		= "Ghost mode"
						newCameraSceneNode	= _ghostCameraSceneNode
					end,

					-- Movie mode
					[Interaction.Mode.MOVIE] = function()
						modeChangedText		= "Movie mode"
						newCameraSceneNode	= _ghostCameraSceneNode	-- Use the ghost camera for the movie
					end,

					-- Making of mode
					[Interaction.Mode.MAKINGOF] = function()
						modeChangedText		= "Making of mode"
						newCameraSceneNode	= _makingOfCameraSceneNode
					end,

					-- Unkown mode
					[Interaction.Mode.UNKNOWN] = function()
						-- Should not happen...
					end,
				}

				-- Execute the "kind of" switch/case statement
				action[newMode]()

				-- Show mode changed text for 5 seconds?
				if showText and modeChangedText ~= nil and not cppApplication:IsExpertMode() then
					luaApplication.ShowText(modeChangedText, 5)
				end

				-- Set camera...
				if newCameraSceneNode ~= nil then
					-- If not movie or making of mode...
					if _mode ~= Interaction.Mode.MOVIE and _mode ~= Interaction.Mode.MAKINGOF then
						-- Get the currently set camera scene node
						local currentCameraSceneNode = cppApplication:GetCamera()

						-- Place the new camera into the same scene container as the old camera
						if currentCameraSceneNode:GetContainer() ~= nil then
							newCameraSceneNode:SetContainer(currentCameraSceneNode:GetContainer())
						end

						-- Give the new camera the position and rotation of the old camera
						newCameraSceneNode.Position = currentCameraSceneNode.Position
						newCameraSceneNode.Rotation = currentCameraSceneNode.Rotation
					end

					-- Set the new application camera
					cppApplication:SetCamera(newCameraSceneNode)

					-- Start the movie?
					if _mode == Interaction.Mode.MOVIE then
						-- Start the playback
						if cppApplication.IsInternalRelease() then
							-- Just a short movie for the internal release - else we would have to wait to long to test the demo
							camcorder:StartPlayback("ShortMovie")
						else
							camcorder:StartPlayback("Movie")
						end

					-- Start the making of?
					elseif _mode == Interaction.Mode.MAKINGOF then
						-- Start the playback
						_makingOf.StartPlayback()
					end
				end
			end
		end

		--@brief
		--  Slot function is called by C++ when a key is pressed down
		--
		--@param[in] nKey
		--  Pressed key
		--@param[in] nModifiers
		--  Modifier keys pressed
		function this.OnKeyDown(key, modifiers)
			-- Lua does not support switch/case statements, so we just use a Lua table (using if/else in here would be somewhat extreme)
			local action = {
				-- Toggle menu visibility
				[PLGui.Key.ESCAPE] = function()
					-- Get the ingame GUI component
					local ingameGui = cppApplication:GetIngameGui()

					-- Toggle menu visibility
					if ingameGui:IsGuiShown() then
						ingameGui:Hide()
					else
						-- Toggle menu visibility
						ingameGui:ShowMenu(not ingameGui:IsMenuShown())

						-- Show the mouse cursor?
						if ingameGui:IsMenuShown() then
							SetMouseVisible(true)
						end
					end
				end,

				-- Walk mode
				[PLGui.Key.ONE] = function()
					this.OnSetMode(Interaction.Mode.WALK, true)
				end,

				-- Free mode
				[PLGui.Key.TWO] = function()
					this.OnSetMode(Interaction.Mode.FREE, true)
				end,

				-- Ghost mode
				[PLGui.Key.THREE] = function()
					this.OnSetMode(Interaction.Mode.GHOST, true)
				end,

				-- Movie mode
				[PLGui.Key.FOUR] = function()
					this.OnSetMode(Interaction.Mode.MOVIE, true)
				end,

				-- Making of mode
				[PLGui.Key.FIVE] = function()
					this.OnSetMode(Interaction.Mode.MAKINGOF, true)
				end,

				-- Make a screenshot from the current render target
				[PLGui.Key.F12] = function()
					cppApplication:GetScreenshotTool():SaveScreenshot(cppApplication:GetScreenshotTool():GetScreenshotFilename("jpg"))
				end,

				-- Toggle camcorder recording
				[PLGui.Key.R] = function()
					-- This key is only allowed in the internal release as well as only if not movie nor making of mode...
					if cppApplication:IsInternalRelease() and _mode ~= Interaction.Mode.MOVIE and _mode ~= Interaction.Mode.MAKINGOF then
						-- Get the camcorder component
						local camcorder = cppApplication:GetCamcorder()

						-- Toggle camcorder recording
						if camcorder:IsRecording() then
							camcorder:StopRecord()
						else
							camcorder:StartRecord("Test")
						end
					end
				end,

				-- Toggle camcorder playback
				[PLGui.Key.P] = function()
					-- This key is only allowed in the internal release as well as only if not movie nor making of mode...
					if cppApplication:IsInternalRelease() and _mode ~= Interaction.Mode.MOVIE and _mode ~= Interaction.Mode.MAKINGOF then
						-- Get the camcorder component
						local camcorder = cppApplication:GetCamcorder()

						-- Toggle camcorder playback
						if camcorder:IsPlaying() then
							-- Stop the playback
							camcorder:StopPlayback()

							-- Restore previously set mode
							this.OnSetMode(_modeBackup, false)
						else
							-- Backup the current set mode
							_modeBackup = _mode

							-- Set to ghost mode
							this.OnSetMode(Interaction.Mode.GHOST, false)

							-- Start the playback
							camcorder:StartPlayback("Test")
						end
					end
				end,
			}

			-- Execute the "kind of" switch/case statement
			action[key]()
		end

		--@brief
		--  Slot function is called by C++ after a scene has been loaded
		function this.OnSceneLoadingFinished()
			-- Get the scene container
			local scene = cppApplication:GetScene()
			if scene ~= nil then
				-- Get references to important scene nodes - because they move through the scene, they may
				-- change their scene container and therefore change their name....

				-- Walk camera scene node
				_walkCameraSceneNode = scene:GetByName("Container.kanal3.WalkCamera")

				-- Free camera scene node
				_freeCameraSceneNode = scene:GetByName("Container.kanal3.FreeCamera")

				-- Ghost camera scene node
				_ghostCameraSceneNode = scene:GetByName("Container.kanal3.GhostCamera")

				-- Making of camera scene node
				_makingOfCameraSceneNode = scene:GetByName("Container.WineCellar.MakingOfCamera")
			end

			-- The offical release should always start with the movie mode
			if cppApplication:IsInternalRelease() then
				-- Internal release
				this.OnSetMode(Interaction.Mode.WALK, false)
			else
				-- Set movie but, but do not show the mode changed text
				this.OnSetMode(Interaction.Mode.MOVIE, false)
			end
		end

		--@brief
		--  Slot function is called by C++ when the camcorder playback has been finished
		function this.OnMoviePlaybackFinished()
			-- Change into the making of mode
			this.OnSetMode(Interaction.Mode.MAKINGOF, true)
		end

		--@brief
		--  Slot function is called by C++  when the mouse is moved
		--
		--@param[in] pos
		--  Mouse position within the window
		function this.OnMouseMove(pos)
			if _leftMouseButtonDown then
				-- Hide the mouse cursor - we don't want to have one during look around
				SetMouseVisible(false)
			end
		end

		--@brief
		--  Slot function is called by C++  when a mouse button is pressed
		--
		--@param[in] button
		--  Mouse button that is pressed
		--@param[in] pos
		--  Mouse position within the window
		function this.OnMouseButtonDown(button, pos)
			-- Left mouse button
			if button == 0 then
				_leftMouseButtonDown = true
			end
		end

		--@brief
		--  Slot function is called by C++  when a mouse button is released
		--
		--@param[in] button
		--  Mouse button that is released
		--@param[in] pos
		--  Mouse position within the window
		function this.OnMouseButtonUp(button, pos)
			-- Left mouse button
			if button == 0 then
				_leftMouseButtonDown = false

				-- Show the mouse cursor
				SetMouseVisible(true)
			end
		end


		--[-------------------------------------------------------]
		--[ Public class constructor implementation               ]
		--[-------------------------------------------------------]
		-- Get the main window of the application
		local widget = cppApplication:GetMainWindow()
		if widget ~= nil then
			-- Use the script function "OnKeyDown" as slot and connect it with the RTTI "SignalKeyDown"-signal of our RTTI widget class instance
			widget.SignalKeyDown.Connect(this.OnKeyDown)
			local contentWidget = widget:GetContentWidget()
			if contentWidget ~= widget then
				-- [TODO] Linux: Currently we need to listen to the content widget key signals as well ("focus follows mouse"-topic)
				contentWidget.SignalKeyDown.Connect(this.OnKeyDown)

				-- Use the script function "OnMouseMove" as slot and connect it with the RTTI "SignalMouseMove"-signal of our RTTI widget class instance
				contentWidget.SignalMouseMove.Connect(this.OnMouseMove)

				-- Use the script function "OnMouseButtonDown" as slot and connect it with the RTTI "SignalMouseButtonDown"-signal of our RTTI widget class instance
				contentWidget.SignalMouseButtonDown.Connect(this.OnMouseButtonDown)

				-- Use the script function "OnMouseButtonUp" as slot and connect it with the RTTI "SignalMouseButtonUp"-signal of our RTTI widget class instance
				contentWidget.SignalMouseButtonUp.Connect(this.OnMouseButtonUp)
			end
		end

		-- Use the script function "OnSceneLoadingFinished" as slot and connect it with the RTTI "SignalSceneLoadingFinished"-signal of our RTTI application class instance
		cppApplication.SignalSceneLoadingFinished.Connect(this.OnSceneLoadingFinished)

		-- Use the script function "OnSetMode" as slot and connect it with the RTTI "SignalSetMode"-signal of our RTTI application class instance
		cppApplication.SignalSetMode.Connect(this.OnSetMode)

		-- Use the script function "OnMoviePlaybackFinished" as slot and connect it with the RTTI "SignalPlaybackFinished"-signal of our RTTI camcorder class instance
		cppApplication:GetCamcorder().SignalPlaybackFinished.Connect(this.OnMoviePlaybackFinished)

		-- By default, the mouse cursor is visible
		SetMouseVisible(true)


		-- Return the created class instance
		return this
	end


}
