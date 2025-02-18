/**
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */
import { addAlpha, styled, useTheme } from '@superset-ui/core';
import { FC, RefObject, useMemo, ReactNode, useState } from 'react';
import Icons from 'src/components/Icons';
import { DropdownButton } from 'src/components/DropdownButton';
import { DropdownButtonProps } from 'antd/lib/dropdown';
import { Menu, MenuProps } from 'src/components/Menu';

const { SubMenu } = Menu;

type SubMenuItemProps = { key: string; label: string | ReactNode };

export interface DropDownSelectableProps extends Pick<MenuProps, 'onSelect'> {
  ref?: RefObject<HTMLDivElement>;
  icon: ReactNode;
  info?: string;
  menuItems: {
    key: string;
    label: string | ReactNode;
    children?: SubMenuItemProps[];
    divider?: boolean;
  }[];
  selectedKeys?: string[];
}

const StyledDropdownButton = styled(DropdownButton as FC<DropdownButtonProps>)`
  button.ant-btn:first-of-type {
    display: none;
  }
  > button.ant-btn:nth-of-type(2) {
    display: inline-flex;
    background-color: transparent !important;
    height: unset;
    padding: 0;
    border: none;
    width: auto !important;

    .anticon {
      line-height: 0;
    }
    &:after {
      box-shadow: none !important;
    }
  }
`;

const StyledMenu = styled(Menu)`
  ${({ theme }) => `
    box-shadow:
        0 3px 6px -4px ${addAlpha(theme.colors.grayscale.dark2, 0.12)},
        0 6px 16px 0
      ${addAlpha(theme.colors.grayscale.dark2, 0.08)},
        0 9px 28px 8px
      ${addAlpha(theme.colors.grayscale.dark2, 0.05)};
    .info {
      font-size: ${theme.typography.sizes.s}px;
      color: ${theme.colors.grayscale.base};
      padding: ${theme.gridUnit}px ${theme.gridUnit * 3}px ${
        theme.gridUnit
      }px ${theme.gridUnit * 3}px;
    }
    .ant-dropdown-menu-item-selected {
      color: ${theme.colors.grayscale.dark1};
      background-color: ${theme.colors.primary.light5};
    }
  `}
`;

const StyleMenuItem = styled(Menu.Item)<{ divider?: boolean }>`
  display: flex;
  justify-content: space-between;
  > span {
    width: 100%;
  }
  border-bottom: ${({ divider, theme }) =>
    divider ? `1px solid ${theme.colors.grayscale.light3};` : 'none;'};
`;

const StyleSubmenuItem = styled.div`
  display: flex;
  justify-content: space-between;
  width: 100%;
  > div {
    flex-grow: 1;
  }
`;

export default (props: DropDownSelectableProps) => {
  const theme = useTheme();
  const [visible, setVisible] = useState(false);
  const { icon, info, menuItems, selectedKeys, onSelect } = props;

  const handleVisibleChange = setVisible;

  const handleMenuSelect: MenuProps['onSelect'] = info => {
    if (onSelect) {
      onSelect(info);
    }
    setVisible(false);
  };
  const menuItem = useMemo(
    () => (label: string | ReactNode, key: string, divider?: boolean) => (
      <StyleMenuItem key={key} divider={divider}>
        <StyleSubmenuItem>
          {label}
          {selectedKeys?.includes(key) && (
            <Icons.Check
              iconColor={theme.colors.primary.base}
              className="tick-menu-item"
              iconSize="xl"
            />
          )}
        </StyleSubmenuItem>
      </StyleMenuItem>
    ),
    [selectedKeys, theme.colors.primary.base],
  );

  const overlayMenu = useMemo(
    () => (
      <>
        {info && (
          <div className="info" data-test="dropdown-selectable-info">
            {info}
          </div>
        )}
        <StyledMenu
          selectedKeys={selectedKeys}
          onSelect={handleMenuSelect}
          selectable
        >
          {menuItems.map(m =>
            m.children?.length ? (
              <SubMenu
                title={m.label}
                key={m.key}
                data-test="dropdown-selectable-icon-submenu"
              >
                {m.children.map(s => menuItem(s.label, s.key))}
              </SubMenu>
            ) : (
              menuItem(m.label, m.key, m.divider)
            ),
          )}
        </StyledMenu>
      </>
    ),
    [selectedKeys, onSelect, info, menuItems, menuItem, handleMenuSelect],
  );

  return (
    <StyledDropdownButton
      overlay={overlayMenu}
      trigger={['click']}
      icon={icon}
      visible={visible}
      onVisibleChange={handleVisibleChange}
    />
  );
};
